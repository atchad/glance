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
      for checks: PullRequest.CheckState in [.failure, .pending] {
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

  func testMergeControlIsANativeIndependentButtonAndDoesNotOpenTheRow() throws {
    let pr = mergePullRequest()
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keys = KeybindingStore(url: directory.appending(path: "keybindings.json"), watch: false)
    var rowActions: [GlanceAction] = []
    var mergeClicks = 0
    let row = PullRequestRow(pullRequest: pr, preferences: Preferences(), keys: keys,
      perform: { rowActions.append($0) }, editRepositoryColor: {}, isPinned: false, isSelected: false,
      select: {}, isShowingDetails: .constant(false), checksAreCached: false,
      merge: { mergeClicks += 1 })
    let host = NSHostingView(rootView: row.frame(width: 400))
    host.frame.size = host.fittingSize
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    host.layoutSubtreeIfNeeded()
    let button = try XCTUnwrap(mergeTriggers(in: host).first)
    XCTAssertEqual(mergeTriggers(in: host).count, 1)
    XCTAssertTrue(button.isEnabled)
    XCTAssertEqual(button.toolTip, "Enable auto-merge (squash)")
    XCTAssertTrue(button.accessibilityLabel()?.contains("owner/repo #42") == true)
    XCTAssertTrue(button.hitTest(NSPoint(x: button.frame.midX, y: button.frame.midY)) === button)
    button.performClick(nil)
    XCTAssertEqual(mergeClicks, 1)
    XCTAssertTrue(rowActions.isEmpty)
  }

  func testMergeStatesHaveOneTooltipAndBusyOrDisabledControlsAreInert() throws {
    var unavailable = mergePullRequest()
    unavailable.mergeCapabilities?.autoMergeAllowed = false
    for (pr, busy, caption) in [
      (unavailable, false, "Auto-merge disabled in this repo"),
      (mergePullRequest(), true, "Enabling auto-merge…"),
      (mergePullRequest(mergeState: .clean), true, "Merging pull request…"),
      (mergePullRequest(autoMerge: true), true, "Disabling auto-merge…"),
      (mergePullRequest(draft: true), true, "Marking ready for review…"),
      (mergePullRequest(lifecycle: .merged), false, "Merged"),
    ] {
      var clicks = 0
      let host = NSHostingView(rootView: PullRequestMergeButton(pullRequest: pr, isBusy: busy) { clicks += 1 })
      _ = host.fittingSize
      host.layoutSubtreeIfNeeded()
      let button = try XCTUnwrap(mergeTriggers(in: host).first)
      XCTAssertFalse(button.isEnabled)
      XCTAssertFalse((button.cell as? NSButtonCell)?.imageDimsWhenDisabled ?? true)
      XCTAssertEqual(nativeTooltips(in: host).filter { $0 == caption }.count, 1)
      button.activate()
      XCTAssertEqual(clicks, 0)
    }
  }

  func testMergeControlSupportsReturnAndSpaceAndReportsErrorsOnHover() throws {
    var clicks = 0
    let host = NSHostingView(rootView: PullRequestMergeButton(pullRequest: mergePullRequest(),
      error: "Permission changed") { clicks += 1 })
    _ = host.fittingSize
    host.layoutSubtreeIfNeeded()
    let button = try XCTUnwrap(mergeTriggers(in: host).first)
    XCTAssertTrue(button.toolTip?.contains("Permission changed") == true)
    for code: UInt16 in [36, 76, 49] {
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: code)!
      button.keyDown(with: event)
    }
    XCTAssertEqual(clicks, 3)
  }

  func testGreenPullRequestIconHasAnEnabledDisableButton() throws {
    var clicks = 0
    let host = NSHostingView(rootView: PullRequestMergeButton(pullRequest: mergePullRequest(autoMerge: true)) { clicks += 1 })
    _ = host.fittingSize
    host.layoutSubtreeIfNeeded()
    let button = try XCTUnwrap(mergeTriggers(in: host).first)
    XCTAssertTrue(button.isEnabled)
    XCTAssertEqual(button.toolTip, "Disable auto-merge")
    button.performClick(nil)
    XCTAssertEqual(clicks, 1)
  }

  func testDraftIconIsAnEnabledReadyForReviewButton() throws {
    var clicks = 0
    let host = NSHostingView(rootView: PullRequestMergeButton(pullRequest: mergePullRequest(draft: true)) { clicks += 1 })
    _ = host.fittingSize
    host.layoutSubtreeIfNeeded()
    let button = try XCTUnwrap(mergeTriggers(in: host).first)
    XCTAssertTrue(button.isEnabled)
    XCTAssertEqual(button.toolTip, "Mark ready for review")
    button.performClick(nil)
    XCTAssertEqual(clicks, 1)
  }

  func testMergeControlPreservesTwoLineRowHeightAcrossLifecycleStates() {
    for width: CGFloat in [280, 360, 600] {
      let baseline = rowHeight(mergePullRequest(), width: width)
      for pr in [mergePullRequest(autoMerge: true), mergePullRequest(mergeState: .clean),
        mergePullRequest(lifecycle: .merged), mergePullRequest(draft: true)] {
        XCTAssertEqual(rowHeight(pr, width: width), baseline, accuracy: 0.5)
      }
    }
  }

  private func mergeTriggers(in view: NSView) -> [MergeActionTrigger.Trigger] {
    (view as? MergeActionTrigger.Trigger).map { [$0] } ?? view.subviews.flatMap { mergeTriggers(in: $0) }
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
