import AppKit
import SwiftUI
import XCTest
@testable import Glance

final class PullRequestMergeTests: XCTestCase {
  func testOpenPullRequestEnablesAutoMerge() {
    let control = PullRequestMergeControl(pullRequest: mergePullRequest())
    XCTAssertEqual(control.state, .open)
    XCTAssertEqual(control.icon, .pullRequest)
    XCTAssertEqual(control.color, .secondary)
    XCTAssertEqual(control.action, .enableAutoMerge)
    XCTAssertEqual(control.help, "Enable auto-merge (squash)")
  }

  func testEnabledAutoMergeIsGreenAndClickDisablesIt() {
    let control = PullRequestMergeControl(pullRequest: mergePullRequest(autoMerge: true))
    XCTAssertEqual(control.state, .autoMergeEnabled)
    XCTAssertEqual(control.icon, .pullRequest)
    XCTAssertEqual(control.color, .statusGreen)
    XCTAssertEqual(control.action, .disableAutoMerge)
    XCTAssertEqual(control.help, "Disable auto-merge")
  }

  func testDisablingUsesItsOwnPermissionAndDoesNotRequireAMergeMethodOrHeadCommit() {
    var pr = mergePullRequest(autoMerge: true, headOID: nil)
    pr.mergeCapabilities?.preferredMethod = nil
    pr.mergeCapabilities?.autoMergeAllowed = false
    pr.mergeCapabilities?.viewerCanEnableAutoMerge = false
    pr.mergeCapabilities?.viewerCanMerge = false
    XCTAssertEqual(PullRequestMergeControl(pullRequest: pr).action, .disableAutoMerge)
    pr.mergeCapabilities?.viewerCanDisableAutoMerge = false
    XCTAssertNil(PullRequestMergeControl(pullRequest: pr).action)
    pr.mergeCapabilities?.viewerCanDisableAutoMerge = nil
    XCTAssertNil(PullRequestMergeControl(pullRequest: pr).action)
    XCTAssertEqual(PullRequestMergeControl(pullRequest: pr).help, "Auto-merge enabled · disable permission unavailable")
  }

  func testReadyToMergeTakesPrecedenceOverAutoMergeAndDoesNotRequireAuthorship() {
    for enabled in [false, true] {
      let control = PullRequestMergeControl(pullRequest: mergePullRequest(mergeState: .clean, autoMerge: enabled))
      XCTAssertEqual(control.state, .ready)
      XCTAssertEqual(control.icon, .merged)
      XCTAssertEqual(control.color, .statusGreen)
      XCTAssertEqual(control.action, .merge)
      XCTAssertEqual(control.help, "Merge pull request (squash)")
    }
  }

  func testMergedPullRequestIsPurpleAndInertEvenWithStaleReadyMetadata() {
    let pr = mergePullRequest(mergeState: .clean, autoMerge: true, lifecycle: .merged)
    let control = PullRequestMergeControl(pullRequest: pr)
    XCTAssertEqual(control.state, .merged)
    XCTAssertEqual(control.icon, .merged)
    XCTAssertEqual(control.color, .purple)
    XCTAssertNil(control.action)
    XCTAssertEqual(control.help, "Merged")
    XCTAssertNil(pr.rowAttention, "The identity control replaces the old merged attention icon")
  }

  func testDisabledRepositoryUsesExactTooltipButStillAllowsDirectMerge() {
    var pr = mergePullRequest()
    pr.mergeCapabilities?.autoMergeAllowed = false
    var control = PullRequestMergeControl(pullRequest: pr)
    XCTAssertNil(control.action)
    XCTAssertEqual(control.help, "Auto-merge disabled in this repo")
    pr = mergePullRequest(mergeState: .clean)
    pr.mergeCapabilities?.autoMergeAllowed = false
    control = PullRequestMergeControl(pullRequest: pr)
    XCTAssertEqual(control.action, .merge)
  }

  func testUnknownPermissionsAndClosedPullRequestsCannotMutate() {
    for pr in [mergePullRequest(lifecycle: .closed),
      mergePullRequest(lifecycle: nil)] {
      XCTAssertNil(PullRequestMergeControl(pullRequest: pr).action)
    }
    var pr = mergePullRequest()
    pr.mergeCapabilities = nil
    XCTAssertNil(PullRequestMergeControl(pullRequest: pr).action)
    pr = mergePullRequest()
    pr.mergeCapabilities?.viewerCanEnableAutoMerge = false
    XCTAssertNil(PullRequestMergeControl(pullRequest: pr).action)
    pr = mergePullRequest(mergeState: .clean)
    pr.mergeCapabilities?.viewerCanMerge = false
    XCTAssertNil(PullRequestMergeControl(pullRequest: pr).action)
    pr.mergeCapabilities?.viewerCanMerge = true
    pr.mergeCapabilities?.preferredMethod = nil
    XCTAssertNil(PullRequestMergeControl(pullRequest: pr).action)
  }

  func testDraftIconMarksReadyForReviewWithoutNeedingMergePermissionsOrHead() {
    var pr = mergePullRequest(draft: true, headOID: nil)
    pr.mergeCapabilities?.preferredMethod = nil
    pr.mergeCapabilities?.viewerCanMerge = false
    pr.mergeCapabilities?.viewerCanEnableAutoMerge = false
    let control = PullRequestMergeControl(pullRequest: pr)
    XCTAssertEqual(control.state, .draft)
    XCTAssertEqual(control.icon, .draft)
    XCTAssertEqual(control.action, .markReadyForReview)
    XCTAssertEqual(control.help, "Mark ready for review")
    pr.mergeCapabilities?.viewerCanMarkReadyForReview = false
    XCTAssertNil(PullRequestMergeControl(pullRequest: pr).action)
    pr.mergeCapabilities?.viewerCanMarkReadyForReview = nil
    XCTAssertNil(PullRequestMergeControl(pullRequest: pr).action)
    XCTAssertNil(PullRequestMergeControl(pullRequest: mergePullRequest(lifecycle: nil, draft: true)).action)
  }

  func testOnlyKnownMergeableCleanStateOffersDirectMerge() {
    for state: PullRequest.MergeState? in [.blocked, .behind, .conflicting, .unstable, .unknown, nil] {
      XCTAssertNotEqual(PullRequestMergeControl(pullRequest: mergePullRequest(mergeState: state)).action, .merge)
    }
    var pr = mergePullRequest(mergeState: .clean)
    pr.isMergeable = nil
    XCTAssertNotEqual(PullRequestMergeControl(pullRequest: pr).action, .merge)
    pr.isMergeable = false
    XCTAssertNotEqual(PullRequestMergeControl(pullRequest: pr).action, .merge)
    XCTAssertNil(PullRequestMergeControl(pullRequest: mergePullRequest(mergeState: .clean, headOID: nil)).action)
    XCTAssertNil(PullRequestMergeControl(pullRequest: mergePullRequest(mergeState: .clean, headOID: "")).action)
  }

  func testQueuedPullRequestCannotBypassTheMergeQueue() {
    let queued = mergePullRequest(mergeState: .clean, queuePosition: 1)
    XCTAssertNil(PullRequestMergeControl(pullRequest: queued).action)
    XCTAssertNotEqual(PullRequestMergeControl(pullRequest: queued).state, .ready)
  }

  func testMergeStateInformationIsNotDuplicatedInAttentionSlot() {
    XCTAssertNil(mergePullRequest(autoMerge: true).rowAttention)
    XCTAssertNil(mergePullRequest(mergeState: .clean, authored: true).rowAttention)
    XCTAssertNotNil(mergePullRequest(mergeState: .conflicting).rowAttention)
  }

  func testNewCapabilitiesRoundTripAndOlderCacheRemainsReadable() throws {
    let original = mergePullRequest()
    let data = try JSONEncoder().encode(original)
    XCTAssertEqual(try JSONDecoder().decode(PullRequest.self, from: data), original)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json.removeValue(forKey: "mergeCapabilities")
    json.removeValue(forKey: "isMergeable")
    let old = try JSONDecoder().decode(PullRequest.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertNil(old.mergeCapabilities)
    XCTAssertNil(PullRequestMergeControl(pullRequest: old).action)
    var enabled = mergePullRequest(autoMerge: true)
    enabled.mergeCapabilities?.viewerCanDisableAutoMerge = nil
    let legacy = try JSONDecoder().decode(PullRequest.self, from: JSONEncoder().encode(enabled))
    XCTAssertNil(PullRequestMergeControl(pullRequest: legacy).action)
    var draftJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var legacyCapabilities = try XCTUnwrap(draftJSON["mergeCapabilities"] as? [String: Any])
    legacyCapabilities.removeValue(forKey: "viewerCanMarkReadyForReview")
    draftJSON["mergeCapabilities"] = legacyCapabilities
    draftJSON["isDraft"] = true
    let legacyDraft = try JSONDecoder().decode(PullRequest.self,
      from: JSONSerialization.data(withJSONObject: draftJSON))
    XCTAssertNil(legacyDraft.mergeCapabilities?.viewerCanMarkReadyForReview)
    XCTAssertNil(PullRequestMergeControl(pullRequest: legacyDraft).action)
  }
}

func mergePullRequest(
  mergeState: PullRequest.MergeState? = .blocked, autoMerge: Bool = false,
  lifecycle: PullRequest.LifecycleState? = .open, draft: Bool = false, authored: Bool = false,
  headOID: String? = "abc123", queuePosition: Int? = nil
) -> PullRequest {
  var pr = PullRequest(
    id: "PR_merge", number: 42, repository: "owner/repo", title: "Merge controls", author: "author",
    authorAvatarURL: nil, url: URL(string: "https://github.com/owner/repo/pull/42")!,
    branch: "feature", headRefOID: headOID, createdAt: .now, reviewRequestedAt: nil,
    updatedAt: .now, isDraft: draft, reviewDecision: "APPROVED", checksState: .success,
    additions: 1, deletions: 0, labels: [], requestedReviewers: [], viewerReviewState: nil,
    viewerReviewedHeadOID: nil, viewerReviewSubmittedAt: nil,
    hasCurrentApprovalFromOtherReviewer: false, stackPosition: nil, stackSize: nil,
    viewerDidAuthor: authored, mergeState: mergeState, unresolvedConversationCount: 0, checks: nil,
    autoMergeEnabled: autoMerge, mergeQueuePosition: queuePosition, lifecycleState: lifecycle,
    viewerReviewRequested: false)
  pr.isMergeable = true
  pr.mergeCapabilities = .init(autoMergeAllowed: true, viewerCanEnableAutoMerge: true,
    viewerCanMerge: true, preferredMethod: .squash)
  pr.mergeCapabilities?.viewerCanDisableAutoMerge = true
  pr.mergeCapabilities?.viewerCanMarkReadyForReview = true
  return pr
}
