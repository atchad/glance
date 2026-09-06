import Foundation
import XCTest

@testable import Glance

final class RateLimitTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testRetrySecondsAndHTTPDateTakePrecedenceOverReset() throws {
    for retry in ["120", "Fri, 15 Jan 2027 08:02:00 GMT"] {
      let deadline = try deadline(status: 403, headers: ["Retry-After": retry,
        "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000900"])
      XCTAssertEqual(deadline, now.addingTimeInterval(120))
    }
  }

  func testResetAndMalformedHeaderFallback() throws {
    XCTAssertEqual(try deadline(status: 403, headers: ["X-RateLimit-Remaining": "0",
      "X-RateLimit-Reset": "1800000900"]), now.addingTimeInterval(900))
    for invalid in ["NaN", "inf", "-1", "1e300", "nonsense"] {
      XCTAssertEqual(try deadline(status: 429, headers: ["Retry-After": invalid]),
        now.addingTimeInterval(60))
    }
    XCTAssertEqual(try deadline(status: 429), now.addingTimeInterval(60))
    XCTAssertEqual(try deadline(status: 403, headers: ["X-RateLimit-Remaining": "0",
      "X-RateLimit-Reset": "1"]), now.addingTimeInterval(60))
  }

  func testPermissionErrorsAndSuccessfulLastQuotaResponseAreNotRateLimited() throws {
    XCTAssertNil(try deadline(status: 403, data: "{\"message\":\"Resource not accessible\"}"))
    XCTAssertNil(try deadline(status: 200, headers: ["X-RateLimit-Remaining": "0"],
      data: "{\"data\":{}}"))
    XCTAssertNil(try deadline(status: 200, data: "{\"errors\":[{\"message\":\"Invalid query\"}]}"))
  }

  func testGraphQLRateLimitErrorAtHTTP200UsesDeadline() throws {
    XCTAssertEqual(try deadline(status: 200, headers: ["X-RateLimit-Remaining": "0",
      "X-RateLimit-Reset": "1800000900"],
      data: "{\"errors\":[{\"type\":\"RATE_LIMITED\",\"message\":\"API rate limit exceeded\"}]}"),
      now.addingTimeInterval(900))
    XCTAssertEqual(try deadline(status: 403,
      data: "{\"message\":\"You have exceeded a secondary rate limit\"}"), now.addingTimeInterval(60))
  }

  @MainActor
  func testRefreshCooldownRetainsCacheAndBlocksRequestsUntilExpiry() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var calls = 0
    var limitNext = false
    let store = AppStore(storageDirectory: directory) { sections in
      calls += 1
      if limitNext {
        throw GitHubError.rateLimited(until: Date().addingTimeInterval(1))
      }
      return ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: []) })
    }
    store.refresh()
    await finished(store)
    let cachedIDs = Set(store.snapshots.keys)
    let savedAt = store.lastUpdated
    limitNext = true
    store.refresh()
    store.preferences.sections[0].query += " repo:example/repo"
    store.refresh()
    await finished(store)
    XCTAssertEqual(calls, 2)
    XCTAssertEqual(Set(store.snapshots.keys), cachedIDs.subtracting([store.preferences.sections[0].id]))
    XCTAssertEqual(store.lastUpdated, savedAt)
    XCTAssertTrue(store.errorMessage?.contains("Refresh is paused until") == true)
    for _ in 0..<10 { store.refresh() }
    XCTAssertEqual(calls, 2)
    limitNext = false
    try await Task.sleep(for: .milliseconds(1100))
    store.refresh()
    await finished(store)
    XCTAssertEqual(calls, 3)
    XCTAssertNil(store.refreshBlockedUntil)
    XCTAssertNil(store.errorMessage)
  }

  @MainActor
  private func finished(_ store: AppStore) async {
    for _ in 0..<100 {
      if !store.isRefreshing { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Refresh did not finish")
  }

  private func deadline(status: Int, headers: [String: String] = [:], data: String = "{}") throws -> Date? {
    let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://api.github.com/graphql")!,
      statusCode: status, httpVersion: nil, headerFields: headers))
    return GitHubClient.rateLimitDeadline(response: response, data: Data(data.utf8), now: now)
  }
}
