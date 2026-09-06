import Foundation
import XCTest
@testable import Glance

final class ReviewThreadPaginationTests: XCTestCase {
  func testUnresolvedThreadBeyondFirstHundredIsCounted() async throws {
    let result = try await fetch(repeatingCursor: false)
    XCTAssertEqual(result.first?.unresolvedConversationCount, 1)
  }

  func testRepeatedCursorFailsInsteadOfLooping() async throws {
    do {
      _ = try await fetch(repeatingCursor: true)
      XCTFail("Repeated cursor must fail")
    } catch is GitHubError { }
  }

  private func fetch(repeatingCursor: Bool) async throws -> [PullRequest] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appending(path: "Fixtures/personal-review-section.json")
    var fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var graph = fixture["data"] as! [String: Any]
    var search = graph["search"] as! [String: Any]
    var node = (search["nodes"] as! [[String: Any]])[0]
    node["reviewThreads"] = ["totalCount": repeatingCursor ? 201 : 101,
      "nodes": Array(repeating: ["isResolved": true], count: 100),
      "pageInfo": ["hasNextPage": true, "endCursor": "after-100"]]
    search["nodes"] = [node]; graph["search"] = search; fixture["data"] = graph
    let first = try JSONSerialization.data(withJSONObject: fixture)
    ThreadURLProtocol.handler = { request in
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
      let query = payload["query"] as! String
      if query.contains("GlanceSection") { return first }
      XCTAssertTrue(query.contains("GlanceReviewThreads"))
      let variables = payload["variables"] as! [String: String]
      XCTAssertEqual(variables["cursor"], "after-100")
      return try JSONSerialization.data(withJSONObject: ["data": ["node": ["reviewThreads": [
        "totalCount": repeatingCursor ? 201 : 101,
        "nodes": [["isResolved": false]],
        "pageInfo": ["hasNextPage": repeatingCursor, "endCursor": "after-100"]
      ]]]])
    }
    defer { ThreadURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ThreadURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = GitHubClient(session: GitHubSession(credentialProvider: ThreadCredentials()), urlSession: session)
    let result = try await client.fetchAll(sections: [PRSection(name: "Test", query: "is:pr")])
    return result.snapshots.first?.pullRequests ?? []
  }
}
private struct ThreadCredentials: GitHubCredentialProvider {
  func credential() async throws -> GitHubCredential { .init(accessToken: "fixture") }
}
private final class ThreadURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> Data)?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let data = try XCTUnwrap(Self.handler)(request)
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
