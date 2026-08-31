import AppKit
import Foundation

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
  @Published var preferences: Preferences { didSet { savePreferences() } }

  private let client = GitHubClient()
  private var refreshTask: Task<Void, Never>?
  private var timerTask: Task<Void, Never>?

  init() {
    var loaded = Self.load(Preferences.self, from: Self.preferencesURL) ?? .default
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
    preferences = loaded
    if let cache = Self.load(GlanceCache.self, from: Self.cacheURL) {
      snapshots = Dictionary(uniqueKeysWithValues: cache.snapshots.map { ($0.id, $0.pullRequests) })
      viewerLogin = cache.viewerLogin
      lastUpdated = cache.savedAt
    }
  }

  var needsReviewCount: Int {
    count(forQueryContaining: "review-requested:@me")
  }

  var menuBarCount: Int? {
    switch preferences.menuBarCountMode {
    case .none: nil
    case .awaitingReview: needsReviewCount
    case .openedByMe: count(forQueryContaining: "author:@me")
    case .allShown: Set(preferences.sections.flatMap { pullRequests(in: $0).map(\.id) }).count
    }
  }

  func start() {
    guard timerTask == nil else { return }
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

  func refresh() {
    guard !isRefreshing else { return }
    refreshTask?.cancel()
    isRefreshing = true
    errorMessage = nil
    connectionIssue = nil
    let sections = preferences.sections
    refreshTask = Task { [weak self] in
      do {
        let result = try await self?.client.fetchAll(sections: sections)
        guard let self, let result else { return }
        snapshots = Dictionary(
          uniqueKeysWithValues: result.snapshots.map { ($0.id, $0.pullRequests) })
        let activeIDs = Set(result.snapshots.flatMap { $0.pullRequests.map(\.id) })
        let retainedDismissals = preferences.dismissedRevisions.filter {
          activeIDs.contains($0.key)
        }
        if retainedDismissals != preferences.dismissedRevisions {
          preferences.dismissedRevisions = retainedDismissals
        }
        if !result.viewer.isEmpty { viewerLogin = result.viewer }
        lastUpdated = Date()
        isRefreshing = false
        saveCache()
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
    (snapshots[section.id] ?? []).filter { !$0.isDismissed(by: preferences.dismissedRevisions) }
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

  private func count(forQueryContaining qualifier: String) -> Int {
    let matchingIDs = preferences.sections
      .filter { $0.query.contains(qualifier) }
      .flatMap { pullRequests(in: $0) }
      .map(\.id)
    return Set(matchingIDs).count
  }

  private func savePreferences() { Self.save(preferences, to: Self.preferencesURL) }

  private func saveCache() {
    let cache = GlanceCache(
      savedAt: lastUpdated ?? Date(), viewerLogin: viewerLogin,
      snapshots: preferences.sections.map {
        SectionSnapshot(id: $0.id, pullRequests: snapshots[$0.id] ?? [])
      }
    )
    Self.save(cache, to: Self.cacheURL)
  }

  private static var supportDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = base.appending(path: "Glance", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
  private static var preferencesURL: URL { supportDirectory.appending(path: "preferences.json") }
  private static var cacheURL: URL { supportDirectory.appending(path: "cache.json") }

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
