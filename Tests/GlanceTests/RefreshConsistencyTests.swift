import XCTest

@testable import Glance

@MainActor
final class RefreshConsistencyTests: XCTestCase {
  func testChangedSearchDiscardsOldResultAndCoalescesRefreshRequests() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = FetchGate()
    let store = AppStore(storageDirectory: directory, fetchSnapshots: gate.fetch)
    store.refresh()
    await gate.waitForRequest(1)
    store.preferences.sections[0].query = "is:pr is:closed"
    store.refresh()
    store.refresh()
    gate.pending.removeFirst().resume(returning: ("obsolete", []))
    await gate.waitForRequest(2)
    XCTAssertNil(store.viewerLogin)
    XCTAssertNil(store.lastUpdated)
    XCTAssertTrue(store.isRefreshing)
    XCTAssertEqual(gate.queries.last?.first, "is:pr is:closed")
    gate.pending.removeFirst().resume(returning: ("current", []))
    await finish(store)
    XCTAssertEqual(store.viewerLogin, "current")
    XCTAssertEqual(gate.queries.count, 2)
  }

  func testObsoleteFailureDoesNotReplaceCurrentStatus() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = FetchGate()
    let store = AppStore(storageDirectory: directory, fetchSnapshots: gate.fetch)
    store.refresh()
    await gate.waitForRequest(1)
    let original = store.preferences.sections[0].query
    store.preferences.sections[0].query = "is:pr is:closed"
    store.preferences.sections[0].query = original
    gate.pending.removeFirst().resume(throwing: GitHubError.api("Old search failed"))
    await gate.waitForRequest(2)
    XCTAssertNil(store.errorMessage)
    XCTAssertNil(store.connectionIssue)
    gate.pending.removeFirst().resume(returning: ("current", []))
    await finish(store)
    XCTAssertEqual(store.viewerLogin, "current")
  }

  private func storage() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func finish(_ store: AppStore) async {
    for _ in 0..<1000 {
      if !store.isRefreshing { return }
      await Task.yield()
    }
    XCTFail("Refresh did not finish")
  }
}

@MainActor
private final class FetchGate {
  var queries: [[String]] = []
  var pending: [CheckedContinuation<(viewer: String, snapshots: [SectionSnapshot]), Error>] = []

  func fetch(_ sections: [PRSection]) async throws -> (viewer: String, snapshots: [SectionSnapshot]) {
    queries.append(sections.map(\.query))
    return try await withCheckedThrowingContinuation { pending.append($0) }
  }

  func waitForRequest(_ count: Int) async {
    for _ in 0..<1000 {
      if queries.count >= count && !pending.isEmpty { return }
      await Task.yield()
    }
    XCTFail("Expected request did not start")
  }
}
