import XCTest
@testable import Glance

@MainActor
final class ApplicationCommandsTests: XCTestCase {
  func testSelectedPRActionsShareAvailabilityAndExecution() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    let commands = ApplicationCommands(store: store, updates: UpdateController(startingUpdater: false))
    let pr = pullRequest()
    let target = CommandTarget(pullRequest: pr)
    XCTAssertFalse(commands.perform(.dismiss))
    XCTAssertFalse(commands.perform(.wake, target: target))
    XCTAssertFalse(commands.perform(.snoozeChecks, target: target))
    XCTAssertTrue(commands.perform(.pin, target: target))
    XCTAssertTrue(store.preferences.pinnedPullRequests.contains(pr.id))
    XCTAssertTrue(commands.perform(.snoozeHour, target: target))
    XCTAssertFalse(store.preferences.pinnedPullRequests.contains(pr.id))
    XCTAssertTrue(store.isSnoozed(pr))
    XCTAssertFalse(commands.perform(.dismiss, target: target))
    XCTAssertTrue(commands.perform(.wake, target: target))
    XCTAssertFalse(store.isSnoozed(pr))
    // Expired snooze metadata must not block a visible PR's actions.
    store.snooze(pr, condition: .until(.distantPast))
    XCTAssertTrue(commands.perform(.dismiss, target: target))
    XCTAssertEqual(store.preferences.dismissedRevisions[pr.id], pr.revisionKey)
    XCTAssertTrue(commands.perform(.undoDismissal))
    XCTAssertNil(store.preferences.dismissedRevisions[pr.id])
    XCTAssertFalse(commands.perform(.undoDismissal))
  }

  func testScopedCallbacksAndStaleSectionTargets() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    let commands = ApplicationCommands(store: store, updates: UpdateController(startingUpdater: false))
    var actions: [GlanceAction] = []
    let target = CommandTarget(navigate: { actions.append($0) }, focusSearch: { actions.append(.search) })
    XCTAssertTrue(commands.perform(.nextPR, target: target))
    XCTAssertTrue(commands.perform(.search, target: target))
    XCTAssertEqual(actions, [.nextPR, .search])
    XCTAssertFalse(commands.perform(.clearSearch, target: target))
    let section = store.preferences.sections[0]
    XCTAssertTrue(commands.perform(.toggleSection, target: CommandTarget(section: section)))
    XCTAssertTrue(store.preferences.sections[0].isCollapsed)
    XCTAssertTrue(commands.perform(.expandAll))
    XCTAssertFalse(store.preferences.sections.contains { $0.isCollapsed })
    XCTAssertTrue(commands.perform(.collapseAll))
    XCTAssertTrue(store.preferences.sections.allSatisfy { $0.isCollapsed })
    store.preferences.sections.removeAll()
    XCTAssertFalse(commands.perform(.toggleSection, target: CommandTarget(section: section)))
    XCTAssertFalse(commands.perform(.expandAll))
  }

  private func pullRequest() -> PullRequest {
    PullRequest(
      id: "PR_commands", number: 1, repository: "owner/repo", title: "Full title 🐙", author: "author",
      authorAvatarURL: nil, url: URL(string: "https://github.com/owner/repo/pull/1")!,
      branch: "feature", headRefOID: "abc123", createdAt: .now, reviewRequestedAt: nil,
      updatedAt: .now, isDraft: false, reviewDecision: nil, checksState: .success,
      additions: 1, deletions: 0, labels: [], requestedReviewers: [], viewerReviewState: nil,
      viewerReviewedHeadOID: nil, viewerReviewSubmittedAt: nil,
      hasCurrentApprovalFromOtherReviewer: false, stackPosition: nil, stackSize: nil,
      viewerDidAuthor: false, mergeState: nil, unresolvedConversationCount: 0, checks: nil,
      autoMergeEnabled: false, mergeQueuePosition: nil, lifecycleState: .open,
      viewerReviewRequested: false)
  }
}
