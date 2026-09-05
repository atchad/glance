import Foundation
import XCTest

@testable import Glance

final class PRTransitionTests: XCTestCase {
  func testKnownPRBecomesPersonallyRequestedAndOverlappingSectionsDoNotDuplicate() {
    let old = pr(requested: false)
    let requested = pr(requested: true)
    XCTAssertEqual(events([old, old], [requested, requested]), [.reviewRequested])
    XCTAssertTrue(events([requested], [requested, requested]).isEmpty)
    // A verified request can resolve unavailable membership; unknown alone is never personal.
    XCTAssertEqual(events([pr(requested: nil)], [requested]), [.reviewRequested])
    for value: Bool? in [false, nil] {
      XCTAssertTrue(events([old], [pr(requested: value, date: 20)]).isEmpty)
      XCTAssertTrue(events([], [pr(requested: value, date: 20)]).isEmpty)
    }
    XCTAssertTrue(events([old], [pr(requested: true, authored: true)]).isEmpty)
  }

  func testCheckTransitionsDespiteUnchangedReviewHeadline() {
    let pending = pr(requested: true, checks: .pending)
    let failed = pr(requested: true, checks: .failure)
    let passed = pr(requested: true, checks: .success)
    XCTAssertEqual(pending.attention.reason, .reviewRequested)
    XCTAssertEqual(failed.attention.reason, .reviewRequested)
    XCTAssertEqual(passed.attention.reason, .reviewRequested)
    XCTAssertEqual(events([pending], [failed]), [.checksFailed])
    XCTAssertEqual(PRTransition.detect(previous: [pending], current: [failed]).first?.message,
      "Fix failing checks")
    XCTAssertEqual(events([failed], [passed]), [.checksRecovered])
    for state: PullRequest.CheckState in [.pending, .neutral, .unknown] {
      XCTAssertTrue(events([failed], [pr(requested: true, checks: state)]).isEmpty)
    }
    for value in [pending, failed, passed] {
      XCTAssertTrue(events([value], [value]).isEmpty)
    }
    XCTAssertEqual(events([pr(requested: nil, checks: .unknown)],
      [pr(requested: nil, checks: .failure)]), [.checksFailed])
  }

  func testDistinctValidatedRequestDatesRepeatWithoutHeadlineChanges() {
    let first = pr(requested: true, date: 20, reviewedAt: 10)
    let second = pr(requested: true, date: 30, reviewedAt: 10)
    let third = pr(requested: true, date: 40, reviewedAt: 10)
    XCTAssertEqual(first.attention.reason, .reviewRerequested)
    XCTAssertEqual(second.attention.reason, first.attention.reason)
    XCTAssertEqual(events([first, first], [second, second]), [.reviewRerequested])
    XCTAssertEqual(events([second], [third]), [.reviewRerequested])
    XCTAssertTrue(events([second], [second]).isEmpty)
    XCTAssertTrue(events([second], [first]).isEmpty)
    XCTAssertTrue(events([second], [pr(requested: false, date: 40, reviewedAt: 10)]).isEmpty)
    XCTAssertTrue(events([second], [pr(requested: nil, date: 40, reviewedAt: 10)]).isEmpty)
    // Missing-to-present history is enrichment, not proof of a new event during this refresh.
    XCTAssertTrue(events([pr(requested: true)], [first]).isEmpty)
    XCTAssertTrue(events([first], [pr(requested: true)]).isEmpty)
    XCTAssertEqual(events([pr(requested: true, date: 20)],
      [pr(requested: true, date: 30)]), [.reviewRerequested])
  }

  func testDismissedReviewHistorySupportsARepeatedRequest() {
    XCTAssertEqual(events([pr(requested: false, date: 5, reviewedAt: 10)],
      [pr(requested: true, date: 20, reviewedAt: 10)]), [.reviewRerequested])
  }

  func testSimultaneousEventsChooseOneEnabledEventWithoutDelayingOthers() {
    let before = pr(requested: false, checks: .pending)
    let after = pr(requested: true, checks: .failure)
    XCTAssertEqual(events([before], [after]), [.reviewRequested])
    XCTAssertEqual(PRTransition.detect(previous: [before], current: [after],
      enabledEvents: [.checksFailed]).map(\.event), [.checksFailed])
    XCTAssertTrue(PRTransition.detect(previous: [before], current: [after], enabledEvents: []).isEmpty)
    XCTAssertTrue(events([after], [after]).isEmpty)
    let rerequested = pr(requested: true, date: 30, checks: .success, reviewedAt: 10)
    let failed = pr(requested: true, date: 20, checks: .failure, reviewedAt: 10)
    XCTAssertEqual(events([failed], [rerequested]), [.reviewRerequested])
    XCTAssertEqual(PRTransition.detect(previous: [failed], current: [rerequested],
      enabledEvents: [.checksRecovered]).map(\.event), [.checksRecovered])
  }

  func testInactiveAndNewUnrequestedPRsDoNotAlert() {
    for state: PullRequest.LifecycleState in [.closed, .merged] {
      XCTAssertTrue(events([pr(requested: false)], [pr(requested: true, lifecycle: state)]).isEmpty)
    }
    XCTAssertTrue(events([pr(requested: false)], [pr(requested: true, draft: true)]).isEmpty)
    XCTAssertTrue(events([], [pr(requested: false, checks: .failure)]).isEmpty)
  }

  private func events(_ previous: [PullRequest], _ current: [PullRequest]) -> [PRNotificationEvent] {
    PRTransition.detect(previous: previous, current: current).map(\.event)
  }

  private func pr(
    requested: Bool?, date: TimeInterval? = nil, checks: PullRequest.CheckState = .success,
    reviewedAt: TimeInterval? = nil, authored: Bool = false,
    lifecycle: PullRequest.LifecycleState = .open, draft: Bool = false
  ) -> PullRequest {
    PullRequest(
      id: "fixture", number: 1, repository: "example/repo", title: "Controlled notification fixture",
      author: "author", authorAvatarURL: nil, url: URL(string: "https://example.com/pull/1")!,
      branch: "feature", headRefOID: "head", createdAt: .distantPast,
      reviewRequestedAt: date.map { Date(timeIntervalSince1970: $0) }, updatedAt: .distantPast,
      isDraft: draft, reviewDecision: nil, checksState: checks, additions: 1, deletions: 0,
      labels: [], requestedReviewers: ["someone"], viewerReviewState: reviewedAt == nil ? nil : "DISMISSED",
      viewerReviewedHeadOID: reviewedAt == nil ? nil : "head",
      viewerReviewSubmittedAt: reviewedAt.map { Date(timeIntervalSince1970: $0) },
      hasCurrentApprovalFromOtherReviewer: false, stackPosition: nil, stackSize: nil,
      viewerDidAuthor: authored, mergeState: .clean, unresolvedConversationCount: 0, checks: nil,
      autoMergeEnabled: false, mergeQueuePosition: nil, lifecycleState: lifecycle,
      viewerReviewRequested: requested)
  }
}
