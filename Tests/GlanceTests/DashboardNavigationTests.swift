import XCTest

@testable import Glance

final class DashboardNavigationTests: XCTestCase {
  func testCollapsedRowsCannotBeSelectedOrActedOn() {
    let first = PRSection(name: "First", query: "", isCollapsed: true)
    let second = PRSection(name: "Second", query: "", isCollapsed: true)
    let pr = makePullRequest()
    let selected = DashboardNavigation.RowID(sectionID: first.id, pullRequestID: pr.id)
    let navigation = DashboardNavigation(sections: [(first, [pr]), (second, [pr])], query: "")
    XCTAssertNil(navigation.moved(from: nil, by: 1))
    XCTAssertNil(navigation.moved(from: selected, by: -1))
    XCTAssertNil(navigation.reconciled(selected))
    XCTAssertNil(navigation.pullRequest(for: selected))
    XCTAssertEqual(navigation.items(in: first.id).count, 1, "Collapsed headers retain result counts")
  }

  func testDuplicateOccurrencesFollowRenderedOrderAndCollapseClearsOnlyHiddenSelection() {
    var first = PRSection(name: "First", query: "")
    let second = PRSection(name: "Second", query: "")
    let pr = makePullRequest()
    let other = makePullRequest(id: "PR_2")
    let initial = DashboardNavigation(sections: [(first, [pr, other]), (second, [pr])], query: "")
    let firstID = initial.moved(from: nil, by: 1)
    let middleID = initial.moved(from: firstID, by: 1)
    let duplicateID = initial.moved(from: middleID, by: 1)
    XCTAssertEqual(firstID?.sectionID, first.id)
    XCTAssertEqual(middleID?.pullRequestID, other.id)
    XCTAssertEqual(duplicateID?.sectionID, second.id)
    XCTAssertNotEqual(firstID, duplicateID)
    XCTAssertEqual(initial.moved(from: duplicateID, by: 1), firstID)
    XCTAssertEqual(initial.moved(from: nil, by: -1), duplicateID)
    first.isCollapsed = true
    let collapsed = DashboardNavigation(sections: [(first, [pr, other]), (second, [pr])], query: "")
    XCTAssertNil(collapsed.reconciled(firstID))
    XCTAssertNil(collapsed.pullRequest(for: firstID))
    XCTAssertEqual(collapsed.reconciled(duplicateID), duplicateID)
    XCTAssertEqual(collapsed.moved(from: nil, by: 1), duplicateID)
  }

  func testFilteringAndRefreshReconcileSelectionAndActionTargets() {
    let section = PRSection(name: "First", query: "")
    let pr = makePullRequest(repository: "owner/keep")
    let other = makePullRequest(id: "PR_2", repository: "owner/remove")
    let initial = DashboardNavigation(sections: [(section, [pr, other])], query: "")
    let selected = initial.moved(from: nil, by: 1)
    let otherID = initial.moved(from: selected, by: 1)
    let filtered = DashboardNavigation(sections: [(section, [pr, other])], query: " KEEP ")
    XCTAssertEqual(filtered.items(in: section.id).map(\.id), [pr.id])
    XCTAssertEqual(filtered.reconciled(selected), selected)
    XCTAssertEqual(filtered.pullRequest(for: selected)?.id, pr.id)
    XCTAssertNil(filtered.reconciled(otherID))
    XCTAssertNil(filtered.pullRequest(for: otherID))
    let refreshed = DashboardNavigation(sections: [(section, [])], query: "")
    XCTAssertNil(refreshed.reconciled(selected))
    XCTAssertNil(refreshed.pullRequest(for: selected))
  }

  private func makePullRequest(id: String = "PR_1", repository: String = "owner/repo") -> PullRequest {
    PullRequest(
      id: id, number: 1, repository: repository, title: "Test", author: "author",
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
