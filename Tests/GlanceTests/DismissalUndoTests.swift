import Foundation
import XCTest

@testable import Glance

@MainActor
final class DismissalUndoTests: XCTestCase {
  func testUndoRestoresVisibilityAndPersistsPreviousState() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    let pullRequest = makePullRequest()
    store.preferences.dismissedRevisions[pullRequest.id] = "older-revision"
    store.dismiss(pullRequest)
    XCTAssertTrue(pullRequest.isDismissed(by: store.preferences.dismissedRevisions))
    XCTAssertEqual(store.dismissalToUndo?.title, pullRequest.title)
    store.undoDismissal()
    XCTAssertFalse(pullRequest.isDismissed(by: store.preferences.dismissedRevisions))
    XCTAssertEqual(store.preferences.dismissedRevisions[pullRequest.id], "older-revision")
    XCTAssertNil(store.dismissalToUndo)
    XCTAssertEqual(AppStore(storageDirectory: directory).preferences.dismissedRevisions[pullRequest.id],
      "older-revision")
  }

  func testUndoOnlyRestoresLatestDismissal() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    let first = makePullRequest()
    let second = makePullRequest(id: "PR_2")
    store.dismiss(first)
    store.dismiss(second)
    store.undoDismissal()
    XCTAssertTrue(first.isDismissed(by: store.preferences.dismissedRevisions))
    XCTAssertNil(store.preferences.dismissedRevisions[second.id])
    store.undoDismissal()
    XCTAssertTrue(first.isDismissed(by: store.preferences.dismissedRevisions))
  }

  func testUndoDoesNotOverwriteNewerDismissalState() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    let pullRequest = makePullRequest()
    store.dismiss(pullRequest)
    store.preferences.dismissedRevisions[pullRequest.id] = "newer-revision"
    store.undoDismissal()
    XCTAssertEqual(store.preferences.dismissedRevisions[pullRequest.id], "newer-revision")
    XCTAssertNil(store.dismissalToUndo)
  }

  func testBannerExpiresWithoutUndoingDismissal() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory, dismissalUndoDuration: 0.05)
    let pullRequest = makePullRequest()
    store.dismiss(pullRequest)
    await waitForExpiry(store)
    XCTAssertTrue(pullRequest.isDismissed(by: store.preferences.dismissedRevisions))
  }

  func testInteractionPausesAndResumesExpiry() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory, dismissalUndoDuration: 0.05)
    let source = UUID()
    store.dismiss(makePullRequest())
    store.pauseDismissalUndo(true, source: source)
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertNotNil(store.dismissalToUndo)
    XCTAssertEqual(store.dismissalUndoProgress, 1)
    store.pauseDismissalUndo(false, source: source)
    await waitForExpiry(store)
  }

  func testLaterDismissalGetsNewCountdownAndUndoCancelsIt() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory, dismissalUndoDuration: 0.3)
    store.dismiss(makePullRequest())
    try await Task.sleep(for: .milliseconds(200))
    store.dismiss(makePullRequest(id: "PR_2"))
    XCTAssertEqual(store.dismissalUndoProgress, 1)
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(store.dismissalToUndo?.id, "PR_2")
    store.undoDismissal()
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertNil(store.dismissalToUndo)
    XCTAssertNil(store.preferences.dismissedRevisions["PR_2"])
  }

  private func waitForExpiry(_ store: AppStore) async {
    for _ in 0..<100 {
      if store.dismissalToUndo == nil { return }
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTFail("Dismissal banner did not expire")
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func makePullRequest(
    id: String = "PR_1",
    viewerReviewState: String? = nil,
    viewerReviewedHeadOID: String? = nil,
    hasCurrentApprovalFromOtherReviewer: Bool = false
  ) -> PullRequest {
    PullRequest(
      id: id, number: 1, repository: "owner/repo", title: "Test", author: "author",
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
      autoMergeEnabled: false, mergeQueuePosition: nil, lifecycleState: .open,
      viewerReviewRequested: false
    )
  }
}
