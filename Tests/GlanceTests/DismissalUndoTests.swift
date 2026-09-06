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
