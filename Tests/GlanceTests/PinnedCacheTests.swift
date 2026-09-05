import Foundation
import XCTest

@testable import Glance

@MainActor
final class PinnedCacheTests: XCTestCase {
  func testPinnedApprovalSurvivesRefreshAndOfflineRelaunch() async throws {
    for otherReviewer in [false, true] {
      let directory = try temporaryDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }
      let section = Preferences.default.sections[0]
      let initial = makePullRequest()
      let approved = makePullRequest(
        viewerReviewState: otherReviewer ? nil : "APPROVED",
        viewerReviewedHeadOID: otherReviewer ? nil : "abc123",
        hasCurrentApprovalFromOtherReviewer: otherReviewer)
      var fetched = initial
      var store: AppStore? = AppStore(storageDirectory: directory) { _ in
        ("viewer", [SectionSnapshot(id: section.id, pullRequests: [fetched])])
      }
      store!.preferences.removePullRequestsAfterOtherApproval = otherReviewer
      await refresh(store!)
      store!.togglePin(initial)
      fetched = approved
      await refresh(store!)

      XCTAssertTrue(approved.isHiddenAfterApproval(using: store!.preferences))
      XCTAssertEqual(store!.pullRequests(in: section).map(\.id), [approved.id])
      let cache = try readCache(directory)
      XCTAssertEqual(cache.snapshots.flatMap(\.pullRequests).map(\.id), [approved.id])
      let cachedApproval = try XCTUnwrap(cache.snapshots.flatMap(\.pullRequests).first)
      XCTAssertEqual(cachedApproval.viewerReviewState, approved.viewerReviewState)
      store = nil

      let relaunched = offlineStore(directory)
      XCTAssertTrue(relaunched.preferences.pinnedPullRequests.contains(approved.id))
      XCTAssertEqual(relaunched.pullRequests(in: section).map(\.id), [approved.id])
      await refresh(relaunched)
      XCTAssertEqual(relaunched.connectionIssue, .unavailable)
      XCTAssertEqual(relaunched.pullRequests(in: section).map(\.id), [approved.id])
    }
  }

  func testPinAndUnpinUpdateCacheWithoutAnotherRefresh() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let section = Preferences.default.sections[0]
    let approved = makePullRequest(
      viewerReviewState: "APPROVED", viewerReviewedHeadOID: "abc123")
    let store = AppStore(storageDirectory: directory) { _ in
      ("viewer", [SectionSnapshot(id: section.id, pullRequests: [approved])])
    }
    await refresh(store)
    XCTAssertTrue(try readCache(directory).snapshots.flatMap(\.pullRequests).isEmpty)
    store.togglePin(approved)
    XCTAssertEqual(offlineStore(directory).pullRequests(in: section).map(\.id), [approved.id])
    store.togglePin(approved)
    XCTAssertTrue(try readCache(directory).snapshots.flatMap(\.pullRequests).isEmpty)
    XCTAssertTrue(offlineStore(directory).pullRequests(in: section).isEmpty)
  }

  func testExclusionOverridesPinDuringSaveRefreshAndRelaunch() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let section = Preferences.default.sections[0]
    let approved = makePullRequest(
      viewerReviewState: "APPROVED", viewerReviewedHeadOID: "abc123")
    let store = AppStore(storageDirectory: directory) { _ in
      ("viewer", [SectionSnapshot(id: section.id, pullRequests: [approved])])
    }
    await refresh(store)
    store.togglePin(approved)
    store.preferences.excludedRepositories = [approved.repository]
    XCTAssertTrue(store.pullRequests(in: section).isEmpty)
    XCTAssertTrue(try readCache(directory).snapshots.flatMap(\.pullRequests).isEmpty)
    await refresh(store)
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.isEmpty)
    XCTAssertFalse(store.preferences.pinnedPullRequests.contains(approved.id))
    XCTAssertTrue(offlineStore(directory).pullRequests(in: section).isEmpty)

    // Old cache files can contain excluded metadata: loading must purge it, even if pinned.
    var preferences = store.preferences
    preferences.pinnedPullRequests.insert(approved.id)
    try write(preferences, to: directory.appending(path: "preferences.json"))
    try write(GlanceCache(savedAt: .now, viewerLogin: "viewer", snapshots: [
      SectionSnapshot(id: section.id, pullRequests: [approved])
    ]), to: directory.appending(path: "cache.json"))
    let relaunched = offlineStore(directory)
    XCTAssertTrue(relaunched.snapshots.values.flatMap { $0 }.isEmpty)
    XCTAssertTrue(try readCache(directory).snapshots.flatMap(\.pullRequests).isEmpty)
  }

  private func refresh(_ store: AppStore) async {
    store.refresh()
    for _ in 0..<1000 {
      if !store.isRefreshing { return }
      try? await Task.sleep(for: .milliseconds(1))
    }
    XCTFail("Refresh did not finish")
  }

  private func offlineStore(_ directory: URL) -> AppStore {
    AppStore(storageDirectory: directory) { _ in throw URLError(.notConnectedToInternet) }
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var preferences = Preferences.default
    preferences.notificationsEnabled = false
    preferences.openAtLogin = false
    try write(preferences, to: directory.appending(path: "preferences.json"))
    return directory
  }

  private func write<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(value).write(to: url)
  }

  private func readCache(_ directory: URL) throws -> GlanceCache {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
      GlanceCache.self, from: Data(contentsOf: directory.appending(path: "cache.json")))
  }

  private func makePullRequest(
    viewerReviewState: String? = nil,
    viewerReviewedHeadOID: String? = nil,
    hasCurrentApprovalFromOtherReviewer: Bool = false
  ) -> PullRequest {
    PullRequest(
      id: "PR_1", number: 1, repository: "owner/repo", title: "Test", author: "author",
      authorAvatarURL: nil, url: URL(string: "https://github.com/owner/repo/pull/1")!,
      branch: "feature", headRefOID: "abc123",
      createdAt: .now, reviewRequestedAt: nil, updatedAt: .now, isDraft: false,
      reviewDecision: nil, checksState: .success,
      additions: 1, deletions: 0, labels: [], requestedReviewers: [],
      viewerReviewState: viewerReviewState, viewerReviewedHeadOID: viewerReviewedHeadOID,
      viewerReviewSubmittedAt: nil,
      hasCurrentApprovalFromOtherReviewer: hasCurrentApprovalFromOtherReviewer,
      stackPosition: nil, stackSize: nil, viewerDidAuthor: false,
      mergeState: nil, unresolvedConversationCount: 0, checks: nil,
      autoMergeEnabled: false, mergeQueuePosition: nil, lifecycleState: .open
    )
  }
}
