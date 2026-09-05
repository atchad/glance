import AppKit
import Foundation
import ServiceManagement

enum AppConnectionIssue: Equatable {
  case authentication
  case unavailable
}

@MainActor
final class AppStore: ObservableObject {
  @Published private(set) var snapshots: [UUID: [PullRequest]] = [:]
  @Published private(set) var viewerLogin: String?
  @Published private(set) var isRefreshing = false
  @Published private(set) var lastUpdated: Date?
  @Published var errorMessage: String?
  @Published private(set) var connectionIssue: AppConnectionIssue?
  @Published private(set) var loginItemErrorMessage: String?
  @Published private(set) var notificationAuthorizationMessage: String?
  @Published private(set) var accessibleRepositories: [String] = []
  @Published private(set) var isLoadingRepositories = false
  @Published private(set) var repositoryLoadError: String?
  @Published var preferences: Preferences {
    didSet {
      savePreferences()
      if oldValue.appearanceMode != preferences.appearanceMode {
        Self.applyAppearance(preferences.appearanceMode)
      }
      if oldValue.approvalCachePolicy != preferences.approvalCachePolicy
        || oldValue.pinnedPullRequests != preferences.pinnedPullRequests
        || oldValue.excludedRepositories != preferences.excludedRepositories
      { saveCache() }
    }
  }

  private let client = GitHubClient()
  private lazy var notificationManager = NotificationManager()
  private let fetchSnapshots: ([PRSection]) async throws -> (
    viewer: String, snapshots: [SectionSnapshot]
  )
  private let preferencesURL: URL
  private let cacheURL: URL
  private var refreshTask: Task<Void, Never>?
  private var timerTask: Task<Void, Never>?
  private var hasNotificationBaseline = false

  init(
    storageDirectory: URL? = nil,
    fetchSnapshots: @escaping ([PRSection]) async throws -> (
      viewer: String, snapshots: [SectionSnapshot]
    ) = { try await GitHubClient().fetchAll(sections: $0) }
  ) {
    let directory = storageDirectory ?? Self.supportDirectory
    preferencesURL = directory.appending(path: "preferences.json")
    cacheURL = directory.appending(path: "cache.json")
    self.fetchSnapshots = fetchSnapshots
    var loaded = Self.load(Preferences.self, from: preferencesURL) ?? .default
    for index in loaded.sections.indices {
      switch loaded.sections[index].name {
      case "Needs My Review": loaded.sections[index].name = "For Review"
      case "My Pull Requests": loaded.sections[index].name = "Opened by Me"
      default: break
      }
    }
    let retiredQueries = [
      "is:pr is:open archived:false author:@me review:changes_requested",
      "is:pr is:open archived:false author:@me review:approved status:success -is:draft",
    ]
    loaded.sections.removeAll { retiredQueries.contains($0.query) }
    for index in loaded.sections.indices {
      loaded.sections[index].isCollapsed = false
    }
    preferences = loaded
    Self.applyAppearance(loaded.appearanceMode)
    if let cache = Self.load(GlanceCache.self, from: cacheURL) {
      let cachedSnapshots = Dictionary(
        uniqueKeysWithValues: cache.snapshots.map { ($0.id, $0.pullRequests) })
      snapshots = Self.removingExcludedRepositories(
        from: cachedSnapshots,
        excluded: preferences.excludedRepositories
      )
      viewerLogin = cache.viewerLogin
      lastUpdated = cache.savedAt
      hasNotificationBaseline = true
      if !preferences.excludedRepositories.isEmpty { saveCache() }
    }
  }

  var needsReviewCount: Int {
    count(forQueryContaining: "review-requested:@me")
  }

  var menuBarCount: Int? {
    Self.calculateMenuBarCount(
      mode: preferences.menuBarCountMode,
      includeMyPullRequests: preferences.includeMyPullRequestsInMenuBarCount,
      sections: preferences.sections,
      snapshots: Dictionary(
        uniqueKeysWithValues: preferences.sections.map { ($0.id, pullRequests(in: $0)) }))
  }

  nonisolated static func calculateMenuBarCount(
    mode: MenuBarCountMode,
    includeMyPullRequests: Bool,
    sections: [PRSection],
    snapshots: [UUID: [PullRequest]]
  ) -> Int? {
    let qualifiers: [String]
    switch mode {
    case .none: return nil
    case .actionRequired:
      return Set(
        snapshots.values.flatMap { $0 }
          .filter { $0.attention.level == .actionRequired }
          .map(\.id)
      ).count
    case .readyToMerge:
      return Set(
        snapshots.values.flatMap { $0 }
          .filter { $0.attention.reason == .readyToMerge }
          .map(\.id)
      ).count
    case .awaitingReview:
      qualifiers =
        includeMyPullRequests
        ? ["review-requested:@me", "author:@me"] : ["review-requested:@me"]
    case .openedByMe: qualifiers = ["author:@me"]
    case .allShown: qualifiers = []
    }

    let matchingSections = qualifiers.isEmpty
      ? sections
      : sections.filter { section in qualifiers.contains { section.query.contains($0) } }
    return Set(matchingSections.flatMap { snapshots[$0.id, default: []].map(\.id) }).count
  }

  func start() {
    guard timerTask == nil else { return }
    _ = notificationManager
    configureNotifications()
    refresh()
    timerTask = Task { [weak self] in
      while !Task.isCancelled {
        let interval = self?.preferences.refreshInterval ?? 60
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { break }
        self?.refresh()
      }
    }
  }

  func configureLoginItemAtLaunch() {
    applyLoginItemPreference(preferences.openAtLogin)
  }

  func setOpenAtLogin(_ enabled: Bool) {
    preferences.openAtLogin = enabled
    applyLoginItemPreference(enabled)
  }

  func setNotificationsEnabled(_ enabled: Bool) {
    preferences.notificationsEnabled = enabled
    if enabled { configureNotifications() } else { notificationAuthorizationMessage = nil }
  }

  func loadAccessibleRepositories() async {
    guard !isLoadingRepositories else { return }
    isLoadingRepositories = true
    repositoryLoadError = nil
    do {
      accessibleRepositories = try await client.fetchAccessibleRepositories()
    } catch {
      repositoryLoadError = error.localizedDescription
    }
    isLoadingRepositories = false
  }

  func applyRepositorySelection(_ selected: Set<String>) {
    preferences.excludedRepositories = Self.excludedRepositories(
      all: accessibleRepositories,
      selected: selected
    )
    snapshots = Self.removingExcludedRepositories(
      from: snapshots,
      excluded: preferences.excludedRepositories
    )
    saveCache()
    refresh()
  }

  static func excludedRepositories(all: [String], selected: Set<String>) -> Set<String> {
    Set(all).subtracting(selected)
  }

  static func removingExcludedRepositories(
    from snapshots: [UUID: [PullRequest]],
    excluded: Set<String>
  ) -> [UUID: [PullRequest]] {
    snapshots.mapValues { pullRequests in
      pullRequests.filter { !excluded.contains($0.repository) }
    }
  }

  static func applyAppearance(_ mode: AppearanceMode) {
    NSApplication.shared.appearance =
      switch mode {
      case .system: nil
      case .light: NSAppearance(named: .aqua)
      case .dark: NSAppearance(named: .darkAqua)
      }
  }

  func refresh() {
    guard !isRefreshing else { return }
    refreshTask?.cancel()
    isRefreshing = true
    errorMessage = nil
    connectionIssue = nil
    let sections = preferences.sections
    refreshTask = Task { [weak self] in
      do {
        let result = try await self?.fetchSnapshots(sections)
        guard let self, let result else { return }
        let fetchedSnapshots = Dictionary(
          uniqueKeysWithValues: result.snapshots.map { ($0.id, $0.pullRequests) })
        let nextSnapshots = Self.removingExcludedRepositories(
          from: fetchedSnapshots,
          excluded: preferences.excludedRepositories
        )
        let previousUnique = Self.uniquePullRequests(in: snapshots)
        let nextUnique = Self.uniquePullRequests(in: nextSnapshots)
        let transitions = hasNotificationBaseline
          ? PRTransition.detect(previous: previousUnique, current: nextUnique,
            enabledEvents: preferences.notificationEvents) : []
        snapshots = nextSnapshots
        hasNotificationBaseline = true
        let activeIDs = Set(nextSnapshots.values.flatMap { $0.map(\.id) })
        let retainedDismissals = preferences.dismissedRevisions.filter {
          activeIDs.contains($0.key)
        }
        if retainedDismissals != preferences.dismissedRevisions {
          preferences.dismissedRevisions = retainedDismissals
        }
        preferences.snoozes = preferences.snoozes.filter { id, snooze in
          guard let pullRequest = nextUnique.first(where: { $0.id == id }) else { return false }
          return snooze.isActive(for: pullRequest)
        }
        preferences.pinnedPullRequests.formIntersection(activeIDs)
        if !result.viewer.isEmpty { viewerLogin = result.viewer }
        lastUpdated = Date()
        isRefreshing = false
        saveCache()
        sendNotifications(for: transitions)
      } catch is CancellationError {
        self?.isRefreshing = false
      } catch {
        self?.errorMessage = error.localizedDescription
        self?.connectionIssue = Self.connectionIssue(for: error)
        self?.isRefreshing = false
      }
    }
  }

  func pullRequests(in section: PRSection) -> [PullRequest] {
    let filtered = (snapshots[section.id] ?? []).filter {
      !preferences.excludedRepositories.contains($0.repository)
        && !$0.isDismissed(by: preferences.dismissedRevisions)
        && !isSnoozed($0)
        && (preferences.pinnedPullRequests.contains($0.id)
          || !$0.isHiddenAfterApproval(using: preferences))
    }
    return Self.sort(filtered, by: section.sortMode).enumerated().sorted { left, right in
      let leftPinned = preferences.pinnedPullRequests.contains(left.element.id)
      let rightPinned = preferences.pinnedPullRequests.contains(right.element.id)
      return leftPinned == rightPinned ? left.offset < right.offset : leftPinned
    }.map(\.element)
  }

  nonisolated static func sort(_ pullRequests: [PullRequest], by mode: PRSortMode) -> [PullRequest] {
    guard mode != .github else { return pullRequests }
    return pullRequests.enumerated().sorted { lhs, rhs in
      let left = lhs.element
      let right = rhs.element
      switch mode {
      case .github: return lhs.offset < rhs.offset
      case .attention:
        if left.attention.priority != right.attention.priority {
          return left.attention.priority < right.attention.priority
        }
        if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
      case .reviewRequested:
        let leftDate = left.personalReviewRequestedAt ?? .distantPast
        let rightDate = right.personalReviewRequestedAt ?? .distantPast
        if leftDate != rightDate { return leftDate > rightDate }
      case .updated:
        if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
      case .created:
        if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
      case .repository:
        let comparison = left.repository.localizedStandardCompare(right.repository)
        if comparison != .orderedSame { return comparison == .orderedAscending }
      case .stack:
        let leftPosition = left.stackPosition ?? Int.max
        let rightPosition = right.stackPosition ?? Int.max
        if leftPosition != rightPosition { return leftPosition < rightPosition }
      }
      return left.id < right.id
    }.map(\.element)
  }

  func toggleCollapse(_ section: PRSection) {
    guard let index = preferences.sections.firstIndex(where: { $0.id == section.id }) else {
      return
    }
    preferences.sections[index].isCollapsed.toggle()
  }

  func open(_ pullRequest: PullRequest) { NSWorkspace.shared.open(pullRequest.url) }

  func dismiss(_ pullRequest: PullRequest) {
    preferences.dismissedRevisions[pullRequest.id] = pullRequest.revisionKey
  }

  func togglePin(_ pullRequest: PullRequest) {
    if preferences.pinnedPullRequests.contains(pullRequest.id) {
      preferences.pinnedPullRequests.remove(pullRequest.id)
    } else {
      preferences.pinnedPullRequests.insert(pullRequest.id)
      preferences.snoozes.removeValue(forKey: pullRequest.id)
    }
  }

  func snooze(_ pullRequest: PullRequest, condition: SnoozeCondition) {
    preferences.snoozes[pullRequest.id] = PRSnooze(condition: condition, createdAt: Date())
    preferences.pinnedPullRequests.remove(pullRequest.id)
  }

  func unsnooze(_ pullRequest: PullRequest) {
    preferences.snoozes.removeValue(forKey: pullRequest.id)
  }

  func isSnoozed(_ pullRequest: PullRequest, now: Date = Date()) -> Bool {
    preferences.snoozes[pullRequest.id]?.isActive(for: pullRequest, now: now) == true
  }

  var snoozedPullRequests: [PullRequest] {
    Self.uniquePullRequests(in: snapshots).filter { isSnoozed($0) }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  func validateSectionQuery(_ query: String) async -> String? {
    do {
      try await client.validateSearchQuery(query)
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  static func connectionIssue(for error: Error) -> AppConnectionIssue {
    if let githubError = error as? GitHubError {
      switch githubError {
      case .ghUnavailable, .notAuthenticated: .authentication
      case .invalidResponse, .api: .unavailable
      }
    } else {
      .unavailable
    }
  }

  static func newReviewRequests(
    previous: [UUID: [PullRequest]],
    next: [UUID: [PullRequest]],
    sections: [PRSection]
  ) -> [PullRequest] {
    let reviewSectionIDs = Set(
      sections.filter { $0.query.contains("review-requested:@me") }.map(\.id))
    let previousIDs = Set(reviewSectionIDs.flatMap { previous[$0, default: []].map(\.id) })
    var emittedIDs: Set<String> = []
    return
      reviewSectionIDs
      .flatMap { next[$0, default: []] }
      .filter { !previousIDs.contains($0.id) && emittedIDs.insert($0.id).inserted }
  }

  private func configureNotifications() {
    guard preferences.notificationsEnabled else { return }
    Task { [weak self] in
      do {
        let allowed = try await self?.notificationManager.requestAuthorization() ?? false
        self?.notificationAuthorizationMessage =
          allowed
          ? nil : "Notifications are disabled in System Settings."
      } catch {
        self?.notificationAuthorizationMessage =
          "Couldn’t enable notifications: \(error.localizedDescription)"
      }
    }
  }

  private func sendNotifications(for transitions: [PRTransition]) {
    guard preferences.notificationsEnabled else { return }
    let allowed = transitions.filter {
      preferences.notificationEvents.contains($0.event)
        && !preferences.excludedRepositories.contains($0.pullRequest.repository)
        && !isSnoozed($0.pullRequest)
    }
    notificationManager.notify(about: allowed)
  }

  nonisolated static func uniquePullRequests(in snapshots: [UUID: [PullRequest]]) -> [PullRequest] {
    var unique: [String: PullRequest] = [:]
    for pullRequest in snapshots.values.flatMap({ $0 }) { unique[pullRequest.id] = pullRequest }
    return Array(unique.values)
  }

  private func applyLoginItemPreference(_ enabled: Bool) {
    let service = SMAppService.mainApp
    loginItemErrorMessage = nil
    do {
      if enabled {
        switch service.status {
        case .enabled:
          return
        case .requiresApproval:
          loginItemErrorMessage =
            "Allow Glance in System Settings › General › Login Items to open it automatically."
          return
        case .notRegistered, .notFound:
          try service.register()
        @unknown default:
          try service.register()
        }
      } else if service.status == .enabled || service.status == .requiresApproval {
        try service.unregister()
      }
    } catch {
      loginItemErrorMessage = "Couldn’t update the login item: \(error.localizedDescription)"
    }
  }

  private func count(forQueryContaining qualifier: String) -> Int {
    let matchingIDs = preferences.sections
      .filter { $0.query.contains(qualifier) }
      .flatMap { pullRequests(in: $0) }
      .map(\.id)
    return Set(matchingIDs).count
  }

  private func savePreferences() { Self.save(preferences, to: preferencesURL) }

  private func saveCache() {
    let cache = GlanceCache(
      savedAt: lastUpdated ?? Date(), viewerLogin: viewerLogin,
      snapshots: preferences.sections.map {
        SectionSnapshot(
          id: $0.id,
          pullRequests: (snapshots[$0.id] ?? []).filter {
            !preferences.excludedRepositories.contains($0.repository)
              && (preferences.pinnedPullRequests.contains($0.id)
                || !$0.isHiddenAfterApproval(using: preferences))
          })
      }
    )
    Self.save(cache, to: cacheURL)
  }

  private static var supportDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = base.appending(path: "Glance", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(type, from: data)
  }

  private static func save<T: Encodable>(_ value: T, to url: URL) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value) else { return }
    try? data.write(to: url, options: .atomic)
  }
}
