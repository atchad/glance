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

  func testCollapsedSectionsReopenExpanded() throws {
    let id = UUID()
    let json =
      #"{"id":"\#(id.uuidString)","name":"For Review","query":"is:pr","isCollapsed":true}"#
    let section = try JSONDecoder().decode(PRSection.self, from: Data(json.utf8))
    XCTAssertFalse(section.isCollapsed)

    let encoded = String(decoding: try JSONEncoder().encode(section), as: UTF8.self)
    XCTAssertFalse(encoded.contains("isCollapsed"))
  }

  func testFreshTimestampUsesNaturalCopy() {
    XCTAssertEqual(Date().updatedLabel, "Last updated just now")
  }

  func testOlderPreferencesGainNewDisplayDefaults() throws {
    let json = """
      {"refreshInterval":30,"panelLevel":"floating","sections":[]}
      """
    let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    XCTAssertFalse(preferences.openPanelAtLaunch)
    XCTAssertEqual(preferences.menuBarCountMode, .awaitingReview)
    XCTAssertFalse(preferences.includeMyPullRequestsInMenuBarCount)
    XCTAssertEqual(preferences.appearanceMode, .system)
    XCTAssertFalse(preferences.showLineChanges)
    XCTAssertTrue(preferences.showCheckStatus)
    XCTAssertTrue(preferences.showReviewStatus)
    XCTAssertEqual(preferences.statusDisplayMode, .compactIcons)
    XCTAssertEqual(preferences.timeDisplayMode, .created)
    XCTAssertTrue(preferences.commandClickDismisses)
    XCTAssertTrue(preferences.removePullRequestsAfterApproval)
    XCTAssertFalse(preferences.removePullRequestsAfterOtherApproval)
    XCTAssertTrue(preferences.showChangedPullRequestsAfterApproval)
    XCTAssertTrue(preferences.showRerequestedPullRequestsAfterApproval)
    XCTAssertTrue(preferences.openAtLogin)
    XCTAssertFalse(preferences.notificationsEnabled)
    XCTAssertTrue(preferences.excludedRepositories.isEmpty)
  }

  func testExplicitOpenPanelAtLaunchPreferenceIsPreserved() throws {
    let json = #"{"openPanelAtLaunch":true}"#
    let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    XCTAssertTrue(preferences.openPanelAtLaunch)
  }

  @MainActor
  func testMenuBarCountCanIncludePullRequestsOpenedByViewer() {
    let reviewSection = PRSection(name: "For Review", query: "is:pr review-requested:@me")
    let mineSection = PRSection(name: "Opened by Me", query: "is:pr author:@me")
    let review = makePullRequest(id: "review")
    let mine = makePullRequest(id: "mine")
    let shared = makePullRequest(id: "shared")
    let snapshots = [reviewSection.id: [review, shared], mineSection.id: [mine, shared]]

    XCTAssertEqual(
      AppStore.calculateMenuBarCount(
        mode: .awaitingReview, includeMyPullRequests: false,
        sections: [reviewSection, mineSection], snapshots: snapshots),
      2)
    XCTAssertEqual(
      AppStore.calculateMenuBarCount(
        mode: .awaitingReview, includeMyPullRequests: true,
        sections: [reviewSection, mineSection], snapshots: snapshots),
      3)
    XCTAssertEqual(
      AppStore.calculateMenuBarCount(
        mode: .openedByMe, includeMyPullRequests: false,
        sections: [reviewSection, mineSection], snapshots: snapshots),
      2)
    XCTAssertEqual(
      AppStore.calculateMenuBarCount(
        mode: .allShown, includeMyPullRequests: false,
        sections: [reviewSection, mineSection], snapshots: snapshots),
      3)
    XCTAssertNil(
      AppStore.calculateMenuBarCount(
        mode: .none, includeMyPullRequests: true,
        sections: [reviewSection, mineSection], snapshots: snapshots))
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

  func testApprovalOnCurrentRevisionIsHiddenByDefault() {
    let pullRequest = makePullRequest(
      viewerReviewState: "APPROVED", viewerReviewedHeadOID: "abc123")
    XCTAssertTrue(pullRequest.isHiddenAfterApproval(using: .default))
  }

  func testApprovalFilteringCanBeDisabled() {
    let pullRequest = makePullRequest(
      viewerReviewState: "APPROVED", viewerReviewedHeadOID: "abc123")
    var preferences = Preferences.default
    preferences.removePullRequestsAfterApproval = false
    XCTAssertFalse(pullRequest.isHiddenAfterApproval(using: preferences))
  }

  func testApprovalBySomeoneElseRemainsVisibleByDefault() {
    let pullRequest = makePullRequest(hasCurrentApprovalFromOtherReviewer: true)
    XCTAssertFalse(pullRequest.isHiddenAfterApproval(using: .default))
  }

  func testApprovalBySomeoneElseCanRemovePullRequestFromCache() {
    let pullRequest = makePullRequest(hasCurrentApprovalFromOtherReviewer: true)
    var preferences = Preferences.default
    preferences.removePullRequestsAfterOtherApproval = true
    XCTAssertTrue(pullRequest.isHiddenAfterApproval(using: preferences))
  }

  func testStaleApprovalBySomeoneElseDoesNotRemoveCurrentRevision() {
    let pullRequest = makePullRequest(hasCurrentApprovalFromOtherReviewer: false)
    var preferences = Preferences.default
    preferences.removePullRequestsAfterOtherApproval = true
    XCTAssertFalse(pullRequest.isHiddenAfterApproval(using: preferences))
  }

  func testOtherReviewerApprovalMustBeCurrentAndEffective() {
    let reviews = [
      PullRequest.ReviewSummary(author: "viewer", state: "APPROVED", headOID: "current"),
      PullRequest.ReviewSummary(author: "alice", state: "APPROVED", headOID: "old"),
      PullRequest.ReviewSummary(author: "bob", state: "APPROVED", headOID: "current"),
      PullRequest.ReviewSummary(
        author: "BOB", state: "CHANGES_REQUESTED", headOID: "current"),
      PullRequest.ReviewSummary(author: "carol", state: "COMMENTED", headOID: "current"),
    ]

    XCTAssertFalse(
      PullRequest.hasCurrentApprovalFromOtherReviewer(
        in: reviews, viewer: "VIEWER", headOID: "current"))
    XCTAssertTrue(
      PullRequest.hasCurrentApprovalFromOtherReviewer(
        in: reviews
          + [
            PullRequest.ReviewSummary(
              author: "dave", state: "APPROVED", headOID: "current")
          ],
        viewer: "viewer", headOID: "current"))
  }

  func testOlderCachedPullRequestsRemainDecodable() throws {
    let encoded = try JSONEncoder().encode(makePullRequest())
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json.removeValue(forKey: "hasCurrentApprovalFromOtherReviewer")

    let migrated = try JSONDecoder().decode(
      PullRequest.self, from: JSONSerialization.data(withJSONObject: json))

    XCTAssertNil(migrated.hasCurrentApprovalFromOtherReviewer)
  }

  func testChangedPullRequestReturnsAfterApprovalWhenEnabled() {
    let pullRequest = makePullRequest(
      headRefOID: "new-head", viewerReviewState: "APPROVED",
      viewerReviewedHeadOID: "approved-head")
    XCTAssertFalse(pullRequest.isHiddenAfterApproval(using: .default))

    var preferences = Preferences.default
    preferences.showChangedPullRequestsAfterApproval = false
    XCTAssertTrue(pullRequest.isHiddenAfterApproval(using: preferences))
  }

  func testRerequestedPullRequestReturnsAfterApprovalWhenEnabled() {
    let pullRequest = makePullRequest(
      reviewRequestedAt: Date(timeIntervalSince1970: 200), viewerReviewState: "APPROVED",
      viewerReviewedHeadOID: "abc123",
      viewerReviewSubmittedAt: Date(timeIntervalSince1970: 100))
    XCTAssertFalse(pullRequest.isHiddenAfterApproval(using: .default))

    var preferences = Preferences.default
    preferences.showRerequestedPullRequestsAfterApproval = false
    XCTAssertTrue(pullRequest.isHiddenAfterApproval(using: preferences))
  }

  @MainActor
  func testOnlyNewPullRequestsInReviewSectionsBecomeNotifications() {
    let reviewSection = PRSection(name: "For Review", query: "is:pr review-requested:@me")
    let mineSection = PRSection(name: "Opened by Me", query: "is:pr author:@me")
    let existing = makePullRequest(id: "existing", repository: "owner/api")
    let newReview = makePullRequest(id: "new-review", repository: "owner/web")
    let newMine = makePullRequest(id: "new-mine", repository: "owner/desktop")

    let result = AppStore.newReviewRequests(
      previous: [reviewSection.id: [existing]],
      next: [reviewSection.id: [existing, newReview], mineSection.id: [newMine]],
      sections: [reviewSection, mineSection]
    )

    XCTAssertEqual(result.map(\.id), ["new-review"])
  }

  @MainActor
  func testRepositorySelectionStoresOnlyUncheckedExceptions() {
    let excluded = AppStore.excludedRepositories(
      all: ["owner/api", "owner/web", "team/mobile"],
      selected: ["owner/api", "team/mobile"]
    )
    XCTAssertEqual(excluded, ["owner/web"])
  }

  @MainActor
  func testExcludedRepositoriesAreRemovedFromEveryCachedSection() {
    let firstSection = UUID()
    let secondSection = UUID()
    let hidden = makePullRequest(id: "hidden", repository: "owner/hidden")
    let visible = makePullRequest(id: "visible", repository: "owner/visible")

    let filtered = AppStore.removingExcludedRepositories(
      from: [firstSection: [hidden, visible], secondSection: [hidden]],
      excluded: ["owner/hidden"]
    )

    XCTAssertEqual(filtered[firstSection]?.map(\.id), ["visible"])
    XCTAssertTrue(filtered[secondSection]?.isEmpty == true)
  }

  func testLegacyMutedRepositoriesMigrateToExcludedRepositories() throws {
    let json = #"{"mutedNotificationRepositories":["owner/legacy"]}"#
    let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    XCTAssertEqual(preferences.excludedRepositories, ["owner/legacy"])
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

  private func makePullRequest(
    id: String = "PR_1",
    repository: String = "owner/repo",
    checks: PullRequest.CheckState = .success,
    reviewers: [String] = [],
    headRefOID: String = "abc123",
    reviewRequestedAt: Date? = nil,
    viewerReviewState: String? = nil,
    viewerReviewedHeadOID: String? = nil,
    viewerReviewSubmittedAt: Date? = nil,
    hasCurrentApprovalFromOtherReviewer: Bool = false
  ) -> PullRequest {
    PullRequest(
      id: id, number: 1, repository: repository, title: "Test", author: "author",
      authorAvatarURL: nil, url: URL(string: "https://github.com/owner/repo/pull/1")!,
      branch: "feature", headRefOID: headRefOID,
      createdAt: .now, reviewRequestedAt: reviewRequestedAt, updatedAt: .now, isDraft: false,
      reviewDecision: nil,
      checksState: checks,
      additions: 1, deletions: 0, labels: [], requestedReviewers: reviewers,
      viewerReviewState: viewerReviewState, viewerReviewedHeadOID: viewerReviewedHeadOID,
      viewerReviewSubmittedAt: viewerReviewSubmittedAt,
      hasCurrentApprovalFromOtherReviewer: hasCurrentApprovalFromOtherReviewer,
      stackPosition: nil, stackSize: nil
    )
  }
}
