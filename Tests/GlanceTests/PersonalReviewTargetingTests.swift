import Foundation
import XCTest

@testable import Glance

final class PersonalReviewTargetingTests: XCTestCase {
  func testDecodedCustomSectionsUsePersonalRequestsAndVerifiedTeams() async throws {
    let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appending(path: "Fixtures/personal-review-section.json")
    let fixture = try Data(contentsOf: fixtureURL)
    let recorder = RequestRecorder(fixture: fixture)
    FixtureURLProtocol.handler = { try recorder.response(for: $0) }
    defer { FixtureURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = GitHubClient(
      session: GitHubSession(credentialProvider: FixtureCredentials()), urlSession: session)
    let sections = [PRSection(name: "Custom", query: "is:pr repo:example/repo"),
                    PRSection(name: "Overlap", query: "is:pr author:author")]

    let result = try await client.fetchAll(sections: sections)
    XCTAssertEqual(result.viewer, "viewer")
    XCTAssertEqual(result.snapshots.map(\.id), sections.map(\.id))
    XCTAssertEqual(result.snapshots[0].pullRequests, result.snapshots[1].pullRequests)
    let prs = Dictionary(uniqueKeysWithValues: result.snapshots[0].pullRequests.map { ($0.id, $0) })
    let direct = try XCTUnwrap(prs["direct"])
    XCTAssertEqual(direct.viewerReviewRequested, true)
    XCTAssertEqual(direct.attention.reason, .reviewRequested)
    XCTAssertEqual(direct.reviewRequestedAt, date(1))
    let unrelated = try XCTUnwrap(prs["unrelated"])
    XCTAssertEqual(unrelated.viewerReviewRequested, false)
    XCTAssertNil(unrelated.reviewRequestedAt)
    XCTAssertEqual(unrelated.attention.reason, .active)
    XCTAssertTrue(unrelated.isHiddenAfterApproval(using: Preferences()))
    let team = try XCTUnwrap(prs["relevant-team"])
    XCTAssertEqual(team.viewerReviewRequested, true)
    XCTAssertEqual(team.reviewRequestedAt, date(3))
    XCTAssertEqual(team.attention.reason, .reviewRerequested)
    XCTAssertFalse(team.isHiddenAfterApproval(using: Preferences()))
    XCTAssertEqual(prs["irrelevant-team"]?.viewerReviewRequested, false)
    XCTAssertNil(prs["irrelevant-team"]?.reviewRequestedAt)
    XCTAssertEqual(prs["irrelevant-team"]?.attention.reason, .active)
    XCTAssertNil(prs["unknown-team"]?.viewerReviewRequested)
    XCTAssertNil(prs["unknown-team"]?.personalReviewRequestedAt)
    XCTAssertEqual(prs["unknown-team"]?.attention.reason, .reviewRequestUnknown)
    XCTAssertEqual(prs["removed"]?.attention.reason, .active)
    XCTAssertTrue(try XCTUnwrap(prs["removed"]).isHiddenAfterApproval(using: Preferences()))
    XCTAssertEqual(prs["mixed"]?.viewerReviewRequested, true)
    XCTAssertEqual(prs["mixed"]?.personalReviewRequestedAt, date(3))
    XCTAssertEqual(prs["null-reviewer"]?.attention.reason, .reviewRequestUnknown)
    XCTAssertEqual(prs["truncated"]?.attention.reason, .reviewRequestUnknown)
    XCTAssertEqual(prs["direct-no-history"]?.attention.reason, .reviewRequested)
    XCTAssertNil(prs["direct-no-history"]?.personalReviewRequestedAt)
    XCTAssertEqual(recorder.teamCalls, ["TEAM_YES": 2, "TEAM_NO": 1, "TEAM_UNKNOWN": 1])

    // Old caches may contain a borrowed date: decoding must not turn it into personal evidence.
    var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(team)) as? [String: Any])
    old.removeValue(forKey: "viewerReviewRequested")
    let legacy = try JSONDecoder().decode(PullRequest.self, from: JSONSerialization.data(withJSONObject: old))
    XCTAssertNil(legacy.personalReviewRequestedAt)
    XCTAssertEqual(legacy.attention.reason, .reviewRequestUnknown)
    XCTAssertTrue(legacy.isHiddenAfterApproval(using: Preferences()))
  }

  private func date(_ day: Int) -> Date? {
    ISO8601DateFormatter().date(from: "2026-09-0\(day)T12:00:00Z")
  }
}

private struct FixtureCredentials: GitHubCredentialProvider {
  func credential() async throws -> GitHubCredential { .init(accessToken: "fixture") }
}

private final class RequestRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private let fixture: Data
  private var calls: [String: Int] = [:]
  var teamCalls: [String: Int] { lock.withLock { calls } }
  init(fixture: Data) { self.fixture = fixture }

  func response(for request: URLRequest) throws -> Data {
    var body = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        body.append(contentsOf: buffer.prefix(count))
      }
    }
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let query = try XCTUnwrap(payload["query"] as? String)
    if query.contains("GlanceSection") { return fixture }
    XCTAssertTrue(query.contains("membership: ALL"))
    let variables = try XCTUnwrap(payload["variables"] as? [String: Any])
    XCTAssertEqual(variables["viewer"] as? String, "viewer")
    let id = try XCTUnwrap(variables["teamID"] as? String)
    lock.withLock { calls[id, default: 0] += 1 }
    if id == "TEAM_UNKNOWN" {
      return Data(#"{"data":{"node":null},"errors":[{"message":"Not accessible"}]}"#.utf8)
    }
    let nextPage = id == "TEAM_YES" && variables["cursor"] == nil
    let login = id == "TEAM_YES" && !nextPage ? "VIEWER" : "viewer-similar"
    return try JSONSerialization.data(withJSONObject: ["data": ["node": ["members": [
      "nodes": [["login": login]],
      "pageInfo": ["hasNextPage": nextPage, "endCursor": nextPage ? "next" as Any : NSNull()]
    ]]]])
  }
}

private final class FixtureURLProtocol: URLProtocol {
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
