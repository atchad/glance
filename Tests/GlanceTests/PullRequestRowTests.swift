import AppKit
import SwiftUI
import XCTest
@testable import Glance

@MainActor
final class PullRequestRowTests: XCTestCase {
  private var directory: URL!
  private var keys: KeybindingStore!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    keys = KeybindingStore(url: directory.appendingPathComponent("keybindings.json"), watch: false)
  }

  override func tearDownWithError() throws {
    keys = nil
    try FileManager.default.removeItem(at: directory)
  }

  func testAttentionDoesNotAddHeightToRows() {
    for width: CGFloat in [280, 360, 600] {
      for checks: PullRequest.CheckState in [.failure, .pending, .success] {
        let pullRequest = makePullRequest(checks: checks)
        XCTAssertNotNil(pullRequest.rowAttention)
        let withAttention = rowHeight(pullRequest, width: width, showsAttention: true)
        let withoutAttention = rowHeight(pullRequest, width: width, showsAttention: false)
        XCTAssertEqual(withAttention, withoutAttention, accuracy: 0.5, "\(checks) at \(width)pt")
      }
    }
  }

  func testLongTitlesDoNotCreateAThirdLine() {
    for width: CGFloat in [280, 360, 600] {
      let short = makePullRequest(title: "Fix checks")
      let long = makePullRequest(title: String(repeating: "A long pull request title 🐙 ", count: 30))
      XCTAssertEqual(rowHeight(short, width: width), rowHeight(long, width: width), accuracy: 0.5)
    }
  }

  func testMetadataTooltipsRemainRegisteredAfterRowRedraws() {
    let pullRequest = makePullRequest()
    let host = NSHostingView(rootView: rowView(pullRequest, width: 400))
    for selected in [false, true, false] {
      host.rootView = rowView(pullRequest, width: 400, isSelected: selected)
      _ = host.fittingSize
      host.layoutSubtreeIfNeeded()
      let tooltips = nativeTooltips(in: host)
      for caption in ["Approved", "Checks failed", "Fix failing checks"] {
        XCTAssertTrue(tooltips.contains(caption), "Missing native tooltip: \(caption)")
      }
    }
  }

  private func nativeTooltips(in view: NSView) -> [String] {
    (view.toolTip.map { [$0] } ?? []) + view.subviews.flatMap { nativeTooltips(in: $0) }
  }

  private func rowHeight(
    _ pullRequest: PullRequest, width: CGFloat, showsAttention: Bool = true
  ) -> CGFloat {
    NSHostingView(rootView: rowView(pullRequest, width: width, showsAttention: showsAttention)).fittingSize.height
  }

  private func rowView(
    _ pullRequest: PullRequest, width: CGFloat, showsAttention: Bool = true, isSelected: Bool = false
  ) -> some View {
    var preferences = Preferences()
    preferences.showAttentionReason = showsAttention
    let row = PullRequestRow(
      pullRequest: pullRequest, preferences: preferences,
      keys: keys, perform: { _ in }, editRepositoryColor: {},
      isPinned: false, isSelected: isSelected, select: {},
      isShowingDetails: .constant(false), checksAreCached: false)
    return row.frame(width: width)
  }

  private func makePullRequest(
    title: String = "Fix checks", checks: PullRequest.CheckState = .failure
  ) -> PullRequest {
    PullRequest(
      id: "PR_1", number: 1, repository: "owner/repo", title: title, author: "author",
      authorAvatarURL: nil, url: URL(string: "https://github.com/owner/repo/pull/1")!,
      branch: "feature", headRefOID: "abc123", createdAt: .now, reviewRequestedAt: nil,
      updatedAt: .now, isDraft: false, reviewDecision: "APPROVED", checksState: checks,
      additions: 1, deletions: 0, labels: [], requestedReviewers: [], viewerReviewState: nil,
      viewerReviewedHeadOID: nil, viewerReviewSubmittedAt: nil,
      hasCurrentApprovalFromOtherReviewer: false, stackPosition: nil, stackSize: nil,
      viewerDidAuthor: true, mergeState: .clean, unresolvedConversationCount: 0, checks: nil,
      autoMergeEnabled: false, mergeQueuePosition: nil, lifecycleState: .open,
      viewerReviewRequested: false)
  }
}
