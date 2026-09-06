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

  func testFailedInitialSectionsDoNotCreateLoadedEmptyCache() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory) { sections in
      ("", sections.map {
        SectionSnapshot(id: $0.id, pullRequests: [], errorMessage: "Invalid query")
      })
    }
    store.refresh()
    await finish(store)
    XCTAssertNil(store.lastUpdated)
    XCTAssertNil(store.menuBarCount)
    XCTAssertFalse(store.sectionErrors.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "cache.json").path))
  }

  func testGlobalFailureDoesNotPresentCachedZeroAsAllClear() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = FetchGate()
    let store = AppStore(storageDirectory: directory, fetchSnapshots: gate.fetch)
    store.preferences.menuBarCountMode = .allShown
    store.refresh()
    await gate.waitForRequest(1)
    gate.pending.removeFirst().resume(returning: ("viewer", store.preferences.sections.map {
      SectionSnapshot(id: $0.id, pullRequests: [])
    }))
    await finish(store)
    XCTAssertEqual(store.menuBarCount, 0)
    let lastSuccess = store.lastUpdated
    store.refresh()
    await gate.waitForRequest(2)
    gate.pending.removeFirst().resume(throwing: GitHubError.api("Connection failed"))
    await finish(store)
    XCTAssertNotNil(store.errorMessage)
    XCTAssertNil(store.menuBarCount)
    XCTAssertEqual(store.lastUpdated, lastSuccess)
  }

  func testCacheProvenancePersistsThroughPartialFailureUntilCompleteRefresh() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let initial = AppStore(storageDirectory: directory) { sections in
      ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: []) })
    }
    XCTAssertFalse(initial.isShowingCachedData)
    initial.refresh()
    await finish(initial)
    let gate = FetchGate()
    let restored = AppStore(storageDirectory: directory, fetchSnapshots: gate.fetch)
    XCTAssertTrue(restored.isShowingCachedData)
    restored.refresh()
    await gate.waitForRequest(1)
    gate.pending.removeFirst().resume(returning: ("viewer", restored.preferences.sections.enumerated().map {
      SectionSnapshot(id: $0.element.id, pullRequests: [], errorMessage: $0.offset == 0 ? "Unavailable" : nil)
    }))
    await finish(restored)
    XCTAssertTrue(restored.isShowingCachedData)
    restored.refresh()
    await gate.waitForRequest(2)
    gate.pending.removeFirst().resume(returning: ("viewer", restored.preferences.sections.map {
      SectionSnapshot(id: $0.id, pullRequests: [])
    }))
    await finish(restored)
    XCTAssertFalse(restored.isShowingCachedData)
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
