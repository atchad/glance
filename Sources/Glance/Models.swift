import Foundation
import SwiftUI

struct PullRequest: Codable, Identifiable, Hashable {
  enum CheckState: String, Codable {
    case success, failure, pending, neutral, unknown
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
  let stackPosition: Int?
  let stackSize: Int?

  var revisionKey: String {
    headRefOID ?? updatedAt.ISO8601Format()
  }

  func isDismissed(by revisions: [String: String]) -> Bool {
    revisions[id] == revisionKey
  }

  var attention: PRAttention {
    if isDraft { return .draft }
    if checksState == .failure || reviewDecision == "CHANGES_REQUESTED" { return .blocked }
    if !requestedReviewers.isEmpty { return .needsReview }
    if reviewDecision == "APPROVED" && checksState == .success { return .ready }
    return .active
  }
}

enum PRAttention {
  case blocked, needsReview, ready, draft, active

  var color: Color {
    switch self {
    case .blocked: .red
    case .needsReview: .orange
    case .ready: .green
    case .draft: .secondary
    case .active: .blue
    }
  }
}

struct PRSection: Codable, Identifiable, Hashable {
  var id: UUID
  var name: String
  var query: String
  var isCollapsed: Bool

  init(id: UUID = UUID(), name: String, query: String, isCollapsed: Bool = false) {
    self.id = id
    self.name = name
    self.query = query
    self.isCollapsed = isCollapsed
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

enum MenuBarCountMode: String, Codable, CaseIterable, Identifiable {
  case none
  case awaitingReview
  case openedByMe
  case allShown

  var id: String { rawValue }
  var title: String {
    switch self {
    case .none: "No count"
    case .awaitingReview: "Awaiting my review"
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
  var refreshInterval: TimeInterval = 60
  var panelLevel: PanelLevel = .floating
  var openPanelAtLaunch = true
  var openAtLogin = true
  var sections: [PRSection] = PRSection.defaults
  var menuBarCountMode: MenuBarCountMode = .awaitingReview
  var showAuthor = true
  var showUpdatedAt = true
  var showCheckStatus = true
  var showReviewStatus = true
  var statusDisplayMode: StatusDisplayMode = .compactIcons
  var timeDisplayMode: TimeDisplayMode = .created
  var commandClickDismisses = true
  var notificationsEnabled = true
  var excludedRepositories: Set<String> = []
  var dismissedRevisions: [String: String] = [:]

  static let `default` = Preferences()

  private enum CodingKeys: String, CodingKey {
    case refreshInterval, panelLevel, openPanelAtLaunch, openAtLogin, sections
    case menuBarCountMode, showAuthor, showUpdatedAt, showCheckStatus, showReviewStatus
    case statusDisplayMode, timeDisplayMode, commandClickDismisses, notificationsEnabled
    case excludedRepositories, mutedNotificationRepositories
    case dismissedRevisions
  }

  init() {}

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    refreshInterval = try values.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 60
    panelLevel = try values.decodeIfPresent(PanelLevel.self, forKey: .panelLevel) ?? .floating
    openPanelAtLaunch = try values.decodeIfPresent(Bool.self, forKey: .openPanelAtLaunch) ?? true
    openAtLogin = try values.decodeIfPresent(Bool.self, forKey: .openAtLogin) ?? true
    sections = try values.decodeIfPresent([PRSection].self, forKey: .sections) ?? PRSection.defaults
    menuBarCountMode =
      try values.decodeIfPresent(MenuBarCountMode.self, forKey: .menuBarCountMode)
      ?? .awaitingReview
    showAuthor = try values.decodeIfPresent(Bool.self, forKey: .showAuthor) ?? true
    showUpdatedAt = try values.decodeIfPresent(Bool.self, forKey: .showUpdatedAt) ?? true
    showCheckStatus = try values.decodeIfPresent(Bool.self, forKey: .showCheckStatus) ?? true
    showReviewStatus = try values.decodeIfPresent(Bool.self, forKey: .showReviewStatus) ?? true
    statusDisplayMode =
      try values.decodeIfPresent(StatusDisplayMode.self, forKey: .statusDisplayMode)
      ?? .compactIcons
    timeDisplayMode =
      try values.decodeIfPresent(TimeDisplayMode.self, forKey: .timeDisplayMode) ?? .created
    commandClickDismisses =
      try values.decodeIfPresent(Bool.self, forKey: .commandClickDismisses) ?? true
    notificationsEnabled =
      try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
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
    try values.encode(panelLevel, forKey: .panelLevel)
    try values.encode(openPanelAtLaunch, forKey: .openPanelAtLaunch)
    try values.encode(openAtLogin, forKey: .openAtLogin)
    try values.encode(sections, forKey: .sections)
    try values.encode(menuBarCountMode, forKey: .menuBarCountMode)
    try values.encode(showAuthor, forKey: .showAuthor)
    try values.encode(showUpdatedAt, forKey: .showUpdatedAt)
    try values.encode(showCheckStatus, forKey: .showCheckStatus)
    try values.encode(showReviewStatus, forKey: .showReviewStatus)
    try values.encode(statusDisplayMode, forKey: .statusDisplayMode)
    try values.encode(timeDisplayMode, forKey: .timeDisplayMode)
    try values.encode(commandClickDismisses, forKey: .commandClickDismisses)
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
