import Foundation
import SwiftUI

struct PullRequest: Codable, Identifiable, Hashable {
  struct ReviewSummary {
    let author: String?
    let state: String
    let headOID: String?
  }

  enum CheckState: String, Codable {
    case success, failure, pending, neutral, unknown
  }

  struct Check: Codable, Hashable {
    let name: String
    let state: CheckState
    let detailsURL: URL?
  }

  enum MergeState: String, Codable {
    case clean, blocked, behind, conflicting, unstable, unknown
  }

  enum LifecycleState: String, Codable {
    case open, closed, merged
  }

  let id: String
  let number: Int
  let repository: String
  let title: String
  let author: String
  let authorAvatarURL: URL?
  let url: URL
  let branch: String
  let headRefOID: String?
  let createdAt: Date
  let reviewRequestedAt: Date?
  let updatedAt: Date
  let isDraft: Bool
  let reviewDecision: String?
  let checksState: CheckState
  let additions: Int
  let deletions: Int
  let labels: [String]
  let requestedReviewers: [String]
  let viewerReviewState: String?
  let viewerReviewedHeadOID: String?
  let viewerReviewSubmittedAt: Date?
  let hasCurrentApprovalFromOtherReviewer: Bool?
  let stackPosition: Int?
  let stackSize: Int?
  let viewerDidAuthor: Bool?
  let mergeState: MergeState?
  let unresolvedConversationCount: Int?
  let checks: [Check]?
  let autoMergeEnabled: Bool?
  let mergeQueuePosition: Int?
  let lifecycleState: LifecycleState?

  var revisionKey: String {
    headRefOID ?? updatedAt.ISO8601Format()
  }

  static func lifecycleState(state: String?, merged: Bool?) -> LifecycleState? {
    if merged == true { return .merged }
    switch state {
    case "OPEN": return .open
    case "CLOSED": return .closed
    default: return nil
    }
  }

  func isDismissed(by revisions: [String: String]) -> Bool {
    revisions[id] == revisionKey
  }

  static func hasCurrentApprovalFromOtherReviewer(
    in reviews: [ReviewSummary], viewer: String, headOID: String
  ) -> Bool {
    var latestOtherReviews: [String: ReviewSummary] = [:]
    for review in reviews {
      guard let author = review.author,
        author.caseInsensitiveCompare(viewer) != .orderedSame,
        review.state == "APPROVED" || review.state == "CHANGES_REQUESTED"
          || review.state == "DISMISSED"
      else { continue }
      latestOtherReviews[author.lowercased()] = review
    }
    return latestOtherReviews.values.contains {
      $0.state == "APPROVED" && $0.headOID == headOID
    }
  }

  func isHiddenAfterApproval(using preferences: Preferences) -> Bool {
    if preferences.removePullRequestsAfterOtherApproval,
      hasCurrentApprovalFromOtherReviewer == true
    {
      return true
    }
    guard preferences.removePullRequestsAfterApproval, viewerReviewState == "APPROVED" else {
      return false
    }
    let changedSinceApproval =
      viewerReviewedHeadOID.map { $0 != headRefOID } ?? false
    let reviewWasRerequested =
      reviewRequestedAt.map { requestDate in
        viewerReviewSubmittedAt.map { requestDate > $0 } ?? false
      } ?? false
    if changedSinceApproval && preferences.showChangedPullRequestsAfterApproval { return false }
    if reviewWasRerequested && preferences.showRerequestedPullRequestsAfterApproval { return false }
    return true
  }

  var attention: PRAttentionSummary {
    let authored = viewerDidAuthor == true
    let reviewWasRerequested = reviewRequestedAt.map { requestedAt in
      viewerReviewSubmittedAt.map { requestedAt > $0 } ?? false
    } ?? false
    let changedSinceReview = viewerReviewedHeadOID.map { $0 != headRefOID } ?? false

    if lifecycleState == .merged {
      return .init(level: .informational, reason: .merged, message: "Merged", priority: 950)
    }
    if lifecycleState == .closed {
      return .init(level: .informational, reason: .closed, message: "Closed", priority: 960)
    }
    if isDraft {
      return .init(level: .informational, reason: .draft, message: "Draft", priority: 900)
    }
    if !authored, reviewWasRerequested {
      return .init(
        level: .actionRequired, reason: .reviewRerequested,
        message: "Review requested again", priority: 10)
    }
    if !authored, changedSinceReview, viewerReviewState != nil {
      return .init(
        level: .actionRequired, reason: .commitsSinceReview,
        message: "New commits since your review", priority: 20)
    }
    if !authored, !requestedReviewers.isEmpty {
      return .init(
        level: .actionRequired, reason: .reviewRequested,
        message: "Review requested", priority: 30)
    }
    if authored, reviewDecision == "CHANGES_REQUESTED" {
      return .init(
        level: .actionRequired, reason: .changesRequested,
        message: "Changes requested", priority: 40)
    }
    if mergeState == .conflicting {
      return .init(
        level: .actionRequired, reason: .mergeConflict,
        message: "Resolve merge conflicts", priority: 50)
    }
    if checksState == .failure {
      let count = checks?.filter { $0.state == .failure }.count ?? 0
      let message = count > 1 ? "Fix \(count) failing checks" : "Fix failing checks"
      return .init(level: .actionRequired, reason: .checksFailing, message: message, priority: 60)
    }
    if let count = unresolvedConversationCount, count > 0 {
      let noun = count == 1 ? "conversation" : "conversations"
      let message = authored ? "Resolve \(count) \(noun)" : "\(count) unresolved \(noun)"
      return .init(
        level: authored ? .actionRequired : .waiting, reason: .unresolvedConversations,
        message: message, priority: 70)
    }
    if mergeState == .behind {
      return .init(
        level: authored ? .actionRequired : .waiting, reason: .branchBehind,
        message: "Branch is behind", priority: 80)
    }
    if checksState == .pending {
      return .init(level: .waiting, reason: .checksPending, message: "Checks running", priority: 100)
    }
    if let position = mergeQueuePosition {
      return .init(
        level: .waiting, reason: .mergeQueue,
        message: "Merge queue · position \(position)", priority: 110)
    }
    if autoMergeEnabled == true {
      return .init(
        level: .waiting, reason: .autoMerge, message: "Auto-merge enabled", priority: 120)
    }
    if authored, reviewDecision == "REVIEW_REQUIRED" {
      return .init(
        level: .waiting, reason: .waitingForReviews,
        message: "Waiting for reviews", priority: 130)
    }
    if authored, reviewDecision == "APPROVED", checksState == .success,
      mergeState == .clean || mergeState == nil
    {
      return .init(
        level: .ready, reason: .readyToMerge, message: "Ready to merge", priority: 140)
    }
    return .init(level: .informational, reason: .active, message: "Active", priority: 800)
  }
}

enum PRAttentionLevel: String, Codable {
  case actionRequired, waiting, ready, informational

  var color: Color {
    switch self {
    case .actionRequired: .orange
    case .waiting: .secondary
    case .ready: .green
    case .informational: .secondary
    }
  }
}

enum PRAttentionReason: String, Codable {
  case reviewRequested, reviewRerequested, commitsSinceReview, changesRequested
  case unresolvedConversations, checksFailing, checksPending, mergeConflict, branchBehind
  case waitingForReviews, readyToMerge, autoMerge, mergeQueue, draft, merged, closed, active
}

struct PRAttentionSummary: Equatable {
  let level: PRAttentionLevel
  let reason: PRAttentionReason
  let message: String
  let priority: Int
}

enum PRSortMode: String, Codable, CaseIterable, Identifiable {
  case github, attention, reviewRequested, updated, created, repository, stack

  var id: String { rawValue }
  var title: String {
    switch self {
    case .github: "GitHub order"
    case .attention: "Attention"
    case .reviewRequested: "Review requested"
    case .updated: "Recently updated"
    case .created: "Recently created"
    case .repository: "Repository"
    case .stack: "Stack order"
    }
  }
}

struct PRSection: Codable, Identifiable, Hashable {
  var id: UUID
  var name: String
  var query: String
  var isCollapsed: Bool
  var sortMode: PRSortMode

  init(
    id: UUID = UUID(), name: String, query: String, isCollapsed: Bool = false,
    sortMode: PRSortMode = .attention
  ) {
    self.id = id
    self.name = name
    self.query = query
    self.isCollapsed = isCollapsed
    self.sortMode = sortMode
  }

  private enum CodingKeys: String, CodingKey { case id, name, query, isCollapsed, sortMode }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    query = try values.decode(String.self, forKey: .query)
    isCollapsed = false
    sortMode = try values.decodeIfPresent(PRSortMode.self, forKey: .sortMode) ?? .github
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(name, forKey: .name)
    try values.encode(query, forKey: .query)
    try values.encode(sortMode, forKey: .sortMode)
  }

  static let defaults: [PRSection] = [
    PRSection(name: "For Review", query: "is:pr is:open archived:false review-requested:@me"),
    PRSection(name: "Opened by Me", query: "is:pr is:open archived:false author:@me"),
  ]
}

struct SectionSnapshot: Codable, Identifiable {
  let id: UUID
  let pullRequests: [PullRequest]
}

struct GlanceCache: Codable {
  let savedAt: Date
  let viewerLogin: String?
  let snapshots: [SectionSnapshot]
}

enum PanelLevel: String, Codable, CaseIterable, Identifiable {
  case floating
  case desktop

  var id: String { rawValue }
  var title: String { self == .floating ? "Always on Top" : "Normal Window" }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }
  var title: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }
}

enum MenuBarCountMode: String, Codable, CaseIterable, Identifiable {
  case none
  case awaitingReview
  case actionRequired
  case readyToMerge
  case openedByMe
  case allShown

  var id: String { rawValue }
  var title: String {
    switch self {
    case .none: "No count"
    case .awaitingReview: "Awaiting my review"
    case .actionRequired: "Action required"
    case .readyToMerge: "Ready to merge"
    case .openedByMe: "Opened by me"
    case .allShown: "All PRs shown"
    }
  }
}

enum StatusDisplayMode: String, Codable, CaseIterable, Identifiable {
  case compactIcons
  case labeled

  var id: String { rawValue }
  var title: String { self == .compactIcons ? "Icons with author and time" : "Labeled row" }
}

enum TimeDisplayMode: String, Codable, CaseIterable, Identifiable {
  case created
  case reviewRequested

  var id: String { rawValue }
  var title: String { self == .created ? "PR created" : "Review requested" }
}

struct Preferences: Codable {
  struct ApprovalCachePolicy: Equatable {
    let removesApproved: Bool
    let removesApprovedByOthers: Bool
    let showsChanged: Bool
    let showsRerequested: Bool
  }

  var refreshInterval: TimeInterval = 60
  var appearanceMode: AppearanceMode = .system
  var panelLevel: PanelLevel = .floating
  var openPanelAtLaunch = false
  var openAtLogin = true
  var sections: [PRSection] = PRSection.defaults
  var menuBarCountMode: MenuBarCountMode = .awaitingReview
  var includeMyPullRequestsInMenuBarCount = false
  var showAuthor = true
  var showUpdatedAt = true
  var showLineChanges = false
  var showCheckStatus = true
  var showReviewStatus = true
  var showAttentionReason = true
  var statusDisplayMode: StatusDisplayMode = .compactIcons
  var timeDisplayMode: TimeDisplayMode = .created
  var commandClickDismisses = true
  var removePullRequestsAfterApproval = true
  var removePullRequestsAfterOtherApproval = false
  var showChangedPullRequestsAfterApproval = true
  var showRerequestedPullRequestsAfterApproval = true
  var notificationsEnabled = false
  var excludedRepositories: Set<String> = []
  var dismissedRevisions: [String: String] = [:]

  static let `default` = Preferences()

  var approvalCachePolicy: ApprovalCachePolicy {
    ApprovalCachePolicy(
      removesApproved: removePullRequestsAfterApproval,
      removesApprovedByOthers: removePullRequestsAfterOtherApproval,
      showsChanged: showChangedPullRequestsAfterApproval,
      showsRerequested: showRerequestedPullRequestsAfterApproval)
  }

  private enum CodingKeys: String, CodingKey {
    case refreshInterval, appearanceMode, panelLevel, openPanelAtLaunch, openAtLogin, sections
    case menuBarCountMode, includeMyPullRequestsInMenuBarCount
    case showAuthor, showUpdatedAt, showLineChanges, showCheckStatus, showReviewStatus
    case showAttentionReason
    case statusDisplayMode, timeDisplayMode, commandClickDismisses, notificationsEnabled
    case removePullRequestsAfterApproval, showChangedPullRequestsAfterApproval
    case removePullRequestsAfterOtherApproval
    case showRerequestedPullRequestsAfterApproval
    case excludedRepositories, mutedNotificationRepositories
    case dismissedRevisions
  }

  init() {}

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    refreshInterval = try values.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 60
    appearanceMode =
      try values.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? .system
    panelLevel = try values.decodeIfPresent(PanelLevel.self, forKey: .panelLevel) ?? .floating
    openPanelAtLaunch = try values.decodeIfPresent(Bool.self, forKey: .openPanelAtLaunch) ?? false
    openAtLogin = try values.decodeIfPresent(Bool.self, forKey: .openAtLogin) ?? true
    sections = try values.decodeIfPresent([PRSection].self, forKey: .sections) ?? PRSection.defaults
    menuBarCountMode =
      try values.decodeIfPresent(MenuBarCountMode.self, forKey: .menuBarCountMode)
      ?? .awaitingReview
    includeMyPullRequestsInMenuBarCount =
      try values.decodeIfPresent(Bool.self, forKey: .includeMyPullRequestsInMenuBarCount) ?? false
    showAuthor = try values.decodeIfPresent(Bool.self, forKey: .showAuthor) ?? true
    showUpdatedAt = try values.decodeIfPresent(Bool.self, forKey: .showUpdatedAt) ?? true
    showLineChanges = try values.decodeIfPresent(Bool.self, forKey: .showLineChanges) ?? false
    showCheckStatus = try values.decodeIfPresent(Bool.self, forKey: .showCheckStatus) ?? true
    showReviewStatus = try values.decodeIfPresent(Bool.self, forKey: .showReviewStatus) ?? true
    showAttentionReason =
      try values.decodeIfPresent(Bool.self, forKey: .showAttentionReason) ?? true
    statusDisplayMode =
      try values.decodeIfPresent(StatusDisplayMode.self, forKey: .statusDisplayMode)
      ?? .compactIcons
    timeDisplayMode =
      try values.decodeIfPresent(TimeDisplayMode.self, forKey: .timeDisplayMode) ?? .created
    commandClickDismisses =
      try values.decodeIfPresent(Bool.self, forKey: .commandClickDismisses) ?? true
    removePullRequestsAfterApproval =
      try values.decodeIfPresent(Bool.self, forKey: .removePullRequestsAfterApproval) ?? true
    removePullRequestsAfterOtherApproval =
      try values.decodeIfPresent(Bool.self, forKey: .removePullRequestsAfterOtherApproval) ?? false
    showChangedPullRequestsAfterApproval =
      try values.decodeIfPresent(Bool.self, forKey: .showChangedPullRequestsAfterApproval) ?? true
    showRerequestedPullRequestsAfterApproval =
      try values.decodeIfPresent(Bool.self, forKey: .showRerequestedPullRequestsAfterApproval)
      ?? true
    notificationsEnabled =
      try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
    excludedRepositories =
      try values.decodeIfPresent(Set<String>.self, forKey: .excludedRepositories)
      ?? values.decodeIfPresent(Set<String>.self, forKey: .mutedNotificationRepositories)
      ?? []
    dismissedRevisions =
      try values.decodeIfPresent([String: String].self, forKey: .dismissedRevisions) ?? [:]
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(refreshInterval, forKey: .refreshInterval)
    try values.encode(appearanceMode, forKey: .appearanceMode)
    try values.encode(panelLevel, forKey: .panelLevel)
    try values.encode(openPanelAtLaunch, forKey: .openPanelAtLaunch)
    try values.encode(openAtLogin, forKey: .openAtLogin)
    try values.encode(sections, forKey: .sections)
    try values.encode(menuBarCountMode, forKey: .menuBarCountMode)
    try values.encode(
      includeMyPullRequestsInMenuBarCount, forKey: .includeMyPullRequestsInMenuBarCount)
    try values.encode(showAuthor, forKey: .showAuthor)
    try values.encode(showUpdatedAt, forKey: .showUpdatedAt)
    try values.encode(showLineChanges, forKey: .showLineChanges)
    try values.encode(showCheckStatus, forKey: .showCheckStatus)
    try values.encode(showReviewStatus, forKey: .showReviewStatus)
    try values.encode(showAttentionReason, forKey: .showAttentionReason)
    try values.encode(statusDisplayMode, forKey: .statusDisplayMode)
    try values.encode(timeDisplayMode, forKey: .timeDisplayMode)
    try values.encode(commandClickDismisses, forKey: .commandClickDismisses)
    try values.encode(removePullRequestsAfterApproval, forKey: .removePullRequestsAfterApproval)
    try values.encode(
      removePullRequestsAfterOtherApproval, forKey: .removePullRequestsAfterOtherApproval)
    try values.encode(
      showChangedPullRequestsAfterApproval, forKey: .showChangedPullRequestsAfterApproval)
    try values.encode(
      showRerequestedPullRequestsAfterApproval, forKey: .showRerequestedPullRequestsAfterApproval)
    try values.encode(notificationsEnabled, forKey: .notificationsEnabled)
    try values.encode(excludedRepositories, forKey: .excludedRepositories)
    try values.encode(dismissedRevisions, forKey: .dismissedRevisions)
  }
}

extension Date {
  var ageLabel: String {
    let seconds = max(0, Date().timeIntervalSince(self))
    if seconds < 60 { return "now" }
    if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
    if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
    if seconds < 604_800 { return "\(Int(seconds / 86_400))d ago" }
    return self.formatted(.dateTime.month(.abbreviated).day())
  }

  var updatedLabel: String {
    let seconds = max(0, Date().timeIntervalSince(self))
    if seconds < 60 { return "Last updated just now" }
    if seconds < 3_600 { return "Last updated \(Int(seconds / 60)) min ago" }
    if seconds < 86_400 { return "Last updated \(Int(seconds / 3_600)) hr ago" }
    return "Last updated \(Int(seconds / 86_400)) days ago"
  }
}
