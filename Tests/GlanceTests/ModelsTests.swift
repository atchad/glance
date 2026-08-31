import AppKit
import XCTest

@testable import Glance

final class ModelsTests: XCTestCase {
  func testBlockedAttentionWinsForFailedChecks() {
    let pullRequest = makePullRequest(checks: .failure, reviewers: ["atchad"])
    XCTAssertEqual(String(describing: pullRequest.attention), "blocked")
  }

  func testRequestedReviewNeedsAttention() {
    let pullRequest = makePullRequest(checks: .success, reviewers: ["atchad"])
    XCTAssertEqual(String(describing: pullRequest.attention), "needsReview")
  }

  func testDefaultSectionsCoverPrimaryWorkflows() {
    XCTAssertTrue(PRSection.defaults.contains { $0.query.contains("review-requested:@me") })
    XCTAssertTrue(PRSection.defaults.contains { $0.query.contains("author:@me") })
    XCTAssertEqual(PRSection.defaults.first?.name, "For Review")
    XCTAssertEqual(PRSection.defaults.count, 2)
    XCTAssertFalse(PRSection.defaults.contains { $0.query.contains("changes_requested") })
    XCTAssertFalse(PRSection.defaults.contains { $0.query.contains("review:approved") })
  }

  func testFreshTimestampUsesNaturalCopy() {
    XCTAssertEqual(Date().updatedLabel, "Last updated just now")
  }

  func testOlderPreferencesGainNewDisplayDefaults() throws {
    let json = """
      {"refreshInterval":30,"panelLevel":"floating","openPanelAtLaunch":true,"sections":[]}
      """
    let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    XCTAssertEqual(preferences.menuBarCountMode, .awaitingReview)
    XCTAssertTrue(preferences.showCheckStatus)
    XCTAssertTrue(preferences.showReviewStatus)
    XCTAssertEqual(preferences.statusDisplayMode, .compactIcons)
    XCTAssertEqual(preferences.timeDisplayMode, .created)
    XCTAssertTrue(preferences.commandClickDismisses)
    XCTAssertTrue(preferences.openAtLogin)
  }

  func testAllVendoredOcticonsLoad() {
    for icon in Octicon.allCases {
      XCTAssertNotNil(
        Bundle.module.url(forResource: icon.rawValue, withExtension: "svg"),
        "Missing \(icon.rawValue)"
      )
      XCTAssertGreaterThan(icon.image.size.width, 0, "Failed to decode \(icon.rawValue)")
    }
  }

  @MainActor
  func testConnectionErrorsDistinguishAuthenticationFromOutages() {
    XCTAssertEqual(AppStore.connectionIssue(for: GitHubError.notAuthenticated("")), .authentication)
    XCTAssertEqual(AppStore.connectionIssue(for: URLError(.notConnectedToInternet)), .unavailable)
    XCTAssertEqual(
      AppStore.connectionIssue(for: GitHubError.api("Service unavailable")), .unavailable)
  }

  func testDismissalOnlyAppliesToTheDismissedHeadRevision() {
    let pullRequest = makePullRequest(checks: .success, reviewers: [])
    XCTAssertTrue(pullRequest.isDismissed(by: [pullRequest.id: "abc123"]))
    XCTAssertFalse(pullRequest.isDismissed(by: [pullRequest.id: "new-head-sha"]))
  }

  func testQueryValidationRejectsLocalSyntaxErrorsBeforeNetwork() async {
    do {
      try await GitHubClient().validateSearchQuery("is:open author:@me")
      XCTFail("Expected missing is:pr to fail")
    } catch let error as QueryValidationError {
      XCTAssertEqual(
        error.localizedDescription, "Add “is:pr” so this section only contains pull requests.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    do {
      try await GitHubClient().validateSearchQuery("is:pr \"unfinished")
      XCTFail("Expected unmatched quote to fail")
    } catch let error as QueryValidationError {
      XCTAssertEqual(error.localizedDescription, "The search contains an unmatched quotation mark.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func makePullRequest(checks: PullRequest.CheckState, reviewers: [String]) -> PullRequest {
    PullRequest(
      id: "PR_1", number: 1, repository: "owner/repo", title: "Test", author: "author",
      authorAvatarURL: nil, url: URL(string: "https://github.com/owner/repo/pull/1")!,
      branch: "feature", headRefOID: "abc123",
      createdAt: .now, reviewRequestedAt: nil, updatedAt: .now, isDraft: false, reviewDecision: nil,
      checksState: checks,
      additions: 1, deletions: 0, labels: [], requestedReviewers: reviewers, stackPosition: nil,
      stackSize: nil
    )
  }
}
