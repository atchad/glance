import Foundation
import XCTest

@testable import Glance

final class GitHubHTTPAuthenticationTests: XCTestCase {
  func testUnauthorizedResponsesAcrossAllRequestPathsOfferSignInRecovery() async throws {
    for route in ["repositories", "validation", "sections", "threads", "teams"] {
      var firstPage: Data?
      if route == "threads" || route == "teams" {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
          .appending(path: "Fixtures/personal-review-section.json")
        var fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        if route == "threads" {
          var graph = fixture["data"] as! [String: Any]
          var search = graph["search"] as! [String: Any]
          var node = (search["nodes"] as! [[String: Any]])[0]
          node["reviewThreads"] = ["totalCount": 101, "nodes": [],
            "pageInfo": ["hasNextPage": true, "endCursor": "next"]]
          search["nodes"] = [node]; graph["search"] = search; fixture["data"] = graph
        }
        firstPage = try JSONSerialization.data(withJSONObject: fixture)
      }
      var requestCount = 0
      AuthenticationURLProtocol.handler = {
        requestCount += 1
        if requestCount == 1, let firstPage { return (200, firstPage) }
        return (401, Data("{\"message\":\"Bad credentials\"}".utf8))
      }
      defer { AuthenticationURLProtocol.handler = nil }
      let (client, session) = makeClient()
      defer { session.invalidateAndCancel() }
      do {
        switch route {
        case "repositories": _ = try await client.fetchAccessibleRepositories()
        case "validation": try await client.validateSearchQuery("is:pr")
        default: _ = try await client.fetchAll(sections: [PRSection(name: "Test", query: "is:pr")])
        }
        XCTFail("Expected authentication failure for \(route)")
      } catch let GitHubError.notAuthenticated(message) {
        XCTAssertTrue(message.contains("gh auth login --hostname github.com"), route)
      }
      XCTAssertEqual(requestCount, firstPage == nil ? 1 : 2, route)
    }
  }

  func testForbiddenResponseIsNotMisclassifiedAsAuthentication() async throws {
    AuthenticationURLProtocol.handler = { (403, Data("{\"message\":\"Resource not accessible\"}".utf8)) }
    defer { AuthenticationURLProtocol.handler = nil }
    let (client, session) = makeClient()
    defer { session.invalidateAndCancel() }
    do {
      _ = try await client.fetchAccessibleRepositories()
      XCTFail("Expected API error")
    } catch let GitHubError.api(message) {
      XCTAssertEqual(message, "Resource not accessible")
    }
  }

  func testRateLimitEscapesPerSectionContainment() async throws {
    for status in [429, 200] {
      AuthenticationURLProtocol.handler = {
        (status, Data("{\"errors\":[{\"type\":\"RATE_LIMITED\",\"message\":\"API rate limit exceeded\"}]}".utf8))
      }
      defer { AuthenticationURLProtocol.handler = nil }
      let (client, session) = makeClient()
      defer { session.invalidateAndCancel() }
      do {
        _ = try await client.fetchAll(sections: [PRSection(name: "Test", query: "is:pr")])
        XCTFail("Rate limits must escape section containment")
      } catch let GitHubError.rateLimited(deadline) {
        XCTAssertGreaterThan(deadline.timeIntervalSinceNow, 50)
      }
    }
  }

  private func makeClient() -> (GitHubClient, URLSession) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthenticationURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return (GitHubClient(session: GitHubSession(credentialProvider: HTTPCredentials()),
      urlSession: session), session)
  }
}

private struct HTTPCredentials: GitHubCredentialProvider {
  func credential() async throws -> GitHubCredential { .init(accessToken: "fixture") }
}

private final class AuthenticationURLProtocol: URLProtocol {
  static var handler: (() -> (Int, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let handler = Self.handler else { return }
    let (status, data) = handler()
    let response = HTTPURLResponse(url: request.url!, statusCode: status,
      httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
