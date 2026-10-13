import Foundation
import XCTest
@testable import Glance

final class SectionTimeoutTests: XCTestCase {
  private let gatewayPage = Data("<html><head><title>502 Bad Gateway</title></head></html>".utf8)

  func testGatewayTimeoutRetriesSamePageWithSmallerPageSize() async throws {
    var requestedSizes: [Int] = []
    let fixture = try loadFixture()
    let snapshot = try await fetch { variables in
      let size = variables["first"] as? Int ?? 0
      requestedSizes.append(size)
      XCTAssertNil(variables["cursor"] as? String)
      return size > 2
        ? (502, ["X-GitHub-Request-Id": "ABCD:1234"], self.gatewayPage)
        : (200, [:], fixture)
    }
    XCTAssertNil(snapshot.errorMessage)
    XCTAssertEqual(snapshot.pullRequests.count, 10)
    XCTAssertEqual(requestedSizes.first, GitHubClient.sectionPageSize)
    XCTAssertEqual(requestedSizes, requestedSizes.sorted(by: >))
    XCTAssertEqual(requestedSizes.last, 2)
  }

  func testPersistentGatewayTimeoutExplainsCauseAndKeepsDiagnostics() async throws {
    var requestedSizes: [Int] = []
    let snapshot = try await fetch { variables in
      requestedSizes.append(variables["first"] as? Int ?? 0)
      return (504, ["X-GitHub-Request-Id": "ABCD:1234"], self.gatewayPage)
    }
    XCTAssertEqual(requestedSizes.last, 1)
    let message = try XCTUnwrap(snapshot.errorMessage)
    let lines = message.components(separatedBy: "\n")
    XCTAssertEqual(lines.first, "GitHub timed out before responding (HTTP 504).")
    XCTAssertTrue(message.contains("10 seconds"), message)
    XCTAssertTrue(message.contains("ABCD:1234"), message)
    XCTAssertTrue(message.contains("1 pull request"), message)
  }

  func testOtherHTTPFailuresIncludeGitHubMessageWithoutRetrying() async throws {
    var calls = 0
    let snapshot = try await fetch { _ in
      calls += 1
      return (500, ["X-GitHub-Request-Id": "EFGH:5678"], Data("{\"message\":\"Server Error\"}".utf8))
    }
    XCTAssertEqual(calls, 1)
    let message = try XCTUnwrap(snapshot.errorMessage)
    XCTAssertTrue(message.hasPrefix("GitHub request failed (HTTP 500).\n"), message)
    XCTAssertTrue(message.contains("Server Error"), message)
    XCTAssertTrue(message.contains("EFGH:5678"), message)
  }

  func testErrorLabelShowsFirstLineAndKeepsDetailsForTooltip() {
    XCTAssertEqual(ErrorSummaryLabel.summary(of: "Short").summary, "Short")
    XCTAssertFalse(ErrorSummaryLabel.summary(of: "Short").hasDetails)
    let split = ErrorSummaryLabel.summary(of: "Summary\nDetail one\nDetail two")
    XCTAssertEqual(split.summary, "Summary")
    XCTAssertTrue(split.hasDetails)
  }

  private func loadFixture() throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appending(path: "Fixtures/personal-review-section.json"))
  }

  private func fetch(
    _ respond: @escaping ([String: Any]) throws -> (Int, [String: String], Data)
  ) async throws -> SectionSnapshot {
    TimeoutURLProtocol.handler = { request in
      var body = request.httpBody ?? Data()
      if let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
          let count = stream.read(&bytes, maxLength: bytes.count)
          if count <= 0 { break }; body.append(contentsOf: bytes.prefix(count))
        }
      }
      let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      guard (payload["query"] as? String)?.contains("GlanceSection") == true else {
        return (200, [:], Data("{\"data\":{\"node\":null}}".utf8))
      }
      return try respond(payload["variables"] as? [String: Any] ?? [:])
    }
    defer { TimeoutURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TimeoutURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = GitHubClient(session: GitHubSession(credentialProvider: TimeoutCredentials()), urlSession: session)
    let result = try await client.fetchAll(sections: [PRSection(name: "Test", query: "is:pr")])
    return try XCTUnwrap(result.snapshots.first)
  }
}

private struct TimeoutCredentials: GitHubCredentialProvider {
  func credential() async throws -> GitHubCredential { .init(accessToken: "fixture") }
}

private final class TimeoutURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, headers, data) = try XCTUnwrap(Self.handler)(request)
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
