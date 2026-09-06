import AppKit
import Foundation
import ServiceManagement

enum AppConnectionIssue: Equatable {
  case authentication
  case unavailable
}

@MainActor
final class AppStore: ObservableObject {
  @Published private(set) var sectionErrors: [UUID: String] = [:]
  @Published private(set) var snapshots: [UUID: [PullRequest]] = [:]
  @Published private(set) var viewerLogin: String?
  @Published private(set) var isRefreshing = false
  @Published private(set) var lastUpdated: Date?
  @Published var errorMessage: String?
  @Published private(set) var storageIssues: [String: String] = [:]
  private var blockedStorageURLs: Set<URL> = []
  private var isLoadingStorage = true

  var storageErrorMessage: String? {
    guard !storageIssues.isEmpty else { return nil }
    return storageIssues.sorted { $0.key < $1.key }.map(\.value).joined(separator: "\n")
  }
  @Published private(set) var dismissalUndoProgress = 1.0
  private var dismissalUndoTask: Task<Void, Never>?
  private var dismissalUndoPauses: Set<UUID> = []
  private let dismissalUndoDuration: TimeInterval
  @Published private(set) var dismissalToUndo: (
    id: String, title: String, revision: String, previousRevision: String?
  )?
  @Published var shortcutErrorMessage: String?
  @Published private(set) var connectionIssue: AppConnectionIssue?
  @Published private(set) var loginItemErrorMessage: String?
  @Published private(set) var notificationAuthorizationMessage: String?
  @Published private(set) var accessibleRepositories: [String] = []
  @Published private(set) var isLoadingRepositories = false
  @Published private(set) var repositoryLoadError: String?
  @Published var preferences: Preferences {
    didSet {
      guard !isLoadingStorage,
        oldValue != preferences || storageIssues["preferences.json-save"] != nil
      else { return }
      if oldValue.sections.map(\.id) != preferences.sections.map(\.id)
        || zip(oldValue.sections, preferences.sections).contains(where: { $0.query != $1.query })
      {
        for section in oldValue.sections where !preferences.sections.contains(where: {
          $0.id == section.id && $0.query == section.query
        }) {
          snapshots.removeValue(forKey: section.id)
          sectionErrors.removeValue(forKey: section.id)
        }
        refreshGeneration &+= 1
        if isRefreshing { refreshQueued = true }
        if lastUpdated != nil { saveCache() }
      }
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
  private var refreshGeneration = 0
  private var refreshQueued = false

  init(
    storageDirectory: URL? = nil,
    dismissalUndoDuration: TimeInterval = 5,
    fetchSnapshots: @escaping ([PRSection]) async throws -> (
      viewer: String, snapshots: [SectionSnapshot]
    ) = { try await GitHubClient().fetchAll(sections: $0) }
  ) {
    let directory = storageDirectory ?? Self.supportDirectory
    preferencesURL = directory.appending(path: "preferences.json")
    cacheURL = directory.appending(path: "cache.json")
    self.fetchSnapshots = fetchSnapshots
    self.dismissalUndoDuration =
      dismissalUndoDuration.isFinite && dismissalUndoDuration > 0 ? dismissalUndoDuration : 5
    preferences = .default
    var loaded = load(Preferences.self, from: preferencesURL) ?? .default
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
    if let cache = load(GlanceCache.self, from: cacheURL) {
      let cachedSnapshots = Dictionary(
        cache.snapshots.map { ($0.id, $0.pullRequests) }, uniquingKeysWith: { first, _ in first })
      snapshots = Self.removingExcludedRepositories(
        from: cachedSnapshots,
        excluded: preferences.excludedRepositories
      )
      sectionErrors = Dictionary(cache.snapshots.compactMap { snapshot in
        snapshot.errorMessage.map { (snapshot.id, $0) }
      }, uniquingKeysWith: { first, _ in first })
      if !sectionErrors.isEmpty {
        errorMessage = "Some sections couldn’t refresh. See details below."
        connectionIssue = .unavailable
      }
      viewerLogin = cache.viewerLogin
      lastUpdated = cache.savedAt
      hasNotificationBaseline = true
      if !preferences.excludedRepositories.isEmpty { saveCache() }
    }
    isLoadingStorage = false
  }

  var needsReviewCount: Int {
    count(forQueryContaining: "review-requested:@me")
  }

  var menuBarCount: Int? {
    guard lastUpdated != nil, errorMessage == nil, sectionErrors.isEmpty,
      preferences.sections.allSatisfy({ snapshots[$0.id] != nil }) else { return nil }
    return Self.calculateMenuBarCount(
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
    guard !isRefreshing else {
      refreshQueued = true
      return
    }
    refreshTask?.cancel()
    isRefreshing = true
    errorMessage = nil
    connectionIssue = nil
    let sections = preferences.sections
    let generation = refreshGeneration
    refreshTask = Task { [weak self] in
      guard let self else { return }
      defer {
        isRefreshing = false
        if refreshQueued {
          refreshQueued = false
          refresh()
        }
      }
      do {
        let result = try await fetchSnapshots(sections)
        guard generation == refreshGeneration else { return }
        sectionErrors = Dictionary(uniqueKeysWithValues: result.snapshots.compactMap { snapshot in
          snapshot.errorMessage.map { (snapshot.id, $0) }
        })
        let freshPullRequests = Dictionary(
          result.snapshots.filter { $0.errorMessage == nil }.flatMap(\.pullRequests).map { ($0.id, $0) },
          uniquingKeysWith: { first, _ in first })
        let fetchedSnapshots = Dictionary(uniqueKeysWithValues: result.snapshots.map { snapshot in
          (snapshot.id, snapshot.errorMessage == nil
            ? snapshot.pullRequests : snapshots[snapshot.id, default: []].map { freshPullRequests[$0.id] ?? $0 })
        })
        if !sectionErrors.isEmpty {
          errorMessage = "Some sections couldn’t refresh. See details below."
          connectionIssue = .unavailable
        }
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
        let hasSuccessfulSection = sectionErrors.isEmpty
          || result.snapshots.contains(where: { $0.errorMessage == nil })
        if hasSuccessfulSection { hasNotificationBaseline = true }
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
        if hasSuccessfulSection {
          lastUpdated = Date()
        }
        if lastUpdated != nil { saveCache() }
        sendNotifications(for: transitions)
      } catch is CancellationError {
        return
      } catch {
        guard generation == refreshGeneration else { return }
        errorMessage = error.localizedDescription
        connectionIssue = Self.connectionIssue(for: error)
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
        if left.stackID != right.stackID {
          if let leftID = left.stackID {
            guard let rightID = right.stackID else { return true }
            return leftID < rightID
          }
          return false
        }
        guard left.stackID != nil else { return left.id < right.id }
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
    dismissalUndoTask?.cancel()
    dismissalUndoProgress = 1
    dismissalToUndo = (
      pullRequest.id, pullRequest.title, pullRequest.revisionKey,
      preferences.dismissedRevisions[pullRequest.id])
    preferences.dismissedRevisions[pullRequest.id] = pullRequest.revisionKey
    dismissalUndoTask = Task { [weak self] in
      var previous = ProcessInfo.processInfo.systemUptime
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        guard !Task.isCancelled, let self else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - previous
        previous = now
        guard dismissalUndoPauses.isEmpty else { continue }
        dismissalUndoProgress = max(0, dismissalUndoProgress - elapsed / dismissalUndoDuration)
        if dismissalUndoProgress == 0 {
          dismissalUndoTask = nil
          dismissalToUndo = nil
          return
        }
      }
    }
  }

  func pauseDismissalUndo(_ paused: Bool, source: UUID) {
    if paused { dismissalUndoPauses.insert(source) }
    else { dismissalUndoPauses.remove(source) }
  }

  func undoDismissal() {
    guard let dismissal = dismissalToUndo else { return }
    dismissalUndoTask?.cancel()
    dismissalUndoTask = nil
    dismissalToUndo = nil
    guard preferences.dismissedRevisions[dismissal.id] == dismissal.revision else { return }
    preferences.dismissedRevisions[dismissal.id] = dismissal.previousRevision
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

  func updateSectionQuery(id: UUID, query: String) {
    guard let index = preferences.sections.firstIndex(where: { $0.id == id }) else { return }
    preferences.sections[index].query = query
    refresh()
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

  private func savePreferences() { save(preferences, to: preferencesURL) }

  private func saveCache() {
    let cache = GlanceCache(
      savedAt: lastUpdated ?? Date(), viewerLogin: viewerLogin,
      snapshots: preferences.sections.compactMap { section in
        guard let pullRequests = snapshots[section.id] else { return nil }
        return SectionSnapshot(
          id: section.id,
          pullRequests: pullRequests.filter {
            !preferences.excludedRepositories.contains($0.repository)
              && (preferences.pinnedPullRequests.contains($0.id)
                || !$0.isHiddenAfterApproval(using: preferences))
          }, errorMessage: sectionErrors[section.id])
      }
    )
    save(cache, to: cacheURL)
  }

  private static var supportDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = base.appending(path: "Glance", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let value = try decoder.decode(type, from: data)
      let recoveredPreferences = (value as? Preferences)?.recoveredInvalidValues == true
      let cache = value as? GlanceCache
      let duplicateSnapshots = cache.map {
        Set($0.snapshots.map(\.id)).count != $0.snapshots.count
      } ?? false
      if recoveredPreferences || duplicateSnapshots {
        preserveOriginal(at: url, reason: "Recovered invalid values in")
      }
      return value
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return nil
    } catch {
      preserveOriginal(at: url, reason: "Couldn’t read")
      return nil
    }
  }

  private func preserveOriginal(at url: URL, reason: String) {
    let name = url.lastPathComponent
    let backup = url.appendingPathExtension("recovery-" + UUID().uuidString)
    do {
      try FileManager.default.copyItem(at: url, to: backup)
      storageIssues[name + "-load"] =
        "\(reason) \(name). A recovery copy was saved beside the original."
    } catch {
      blockedStorageURLs.insert(url)
      storageIssues[name + "-load"] =
        "\(reason) \(name). Couldn’t preserve it. Saving this file is disabled; the original is unchanged."
    }
  }

  private func save<T: Encodable>(_ value: T, to url: URL) {
    guard !blockedStorageURLs.contains(url) else { return }
    let key = url.lastPathComponent + "-save"
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(value)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      storageIssues.removeValue(forKey: key)
    } catch {
      storageIssues[key] = "Couldn’t save \(url.lastPathComponent). Recent changes may not survive quitting."
    }
  }
}
