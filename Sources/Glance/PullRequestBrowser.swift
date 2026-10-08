import Combine
import Foundation
import WebKit

@MainActor
protocol PullRequestBrowserPage: AnyObject {
  var hasBeenShown: Bool { get }
  func update(_ pullRequest: PullRequest)
  func show()
  func discard()
  func reloadUnopenedPage()
}

/// Owns live pages independently of window visibility. Queue refreshes update membership,
/// not navigation: an existing page must never reload merely because metadata changed.
@MainActor
final class PullRequestBrowser {
  private(set) var pages: [String: any PullRequestBrowserPage] = [:]
  private(set) var pending: [PullRequest] = []
  private let makePage: @MainActor (PullRequest) -> any PullRequestBrowserPage
  let webSession: GitHubWebSession
  private var signInPage: PullRequestBrowserWindow?
  private var linkPages: [URL: PullRequestBrowserWindow] = [:]
  private var desiredPullRequests: [PullRequest] = []
  private var preloadingEnabled = true
  private var resettingSession = false
  private var preloadTask: Task<Void, Never>?
  private var subscription: AnyCancellable?
  private var authenticationSubscription: AnyCancellable?

  init(dataStore: WKWebsiteDataStore? = nil,
    makePage: (@MainActor (PullRequest) -> any PullRequestBrowserPage)? = nil)
  {
    let session = GitHubWebSession(dataStore: dataStore)
    webSession = session
    self.makePage = makePage ?? { PullRequestBrowserWindow(pullRequest: $0, dataStore: session.dataStore) }
    authenticationSubscription = session.$authenticationRevision.dropFirst().sink { [weak self] _ in
      guard let self, !self.resettingSession else { return }
      for page in self.pages.values where !page.hasBeenShown { page.reloadUnopenedPage() }
    }
  }

  func bind(to store: AppStore) {
    // Published emits before assignment. Deliver on the next run-loop turn so we see
    // the final snapshots and preferences together, including refresh-time cleanup.
    subscription = store.$snapshots.combineLatest(store.$preferences)
      .debounce(for: .zero, scheduler: RunLoop.main)
      .sink { [weak self, weak store] _ in
        guard let self, let store else { return }
        self.setPreloadingEnabled(store.preferences.linkOpening == .glance)
        self.reconcile(store.browserPullRequests)
        self.startPreloading()
      }
    setPreloadingEnabled(store.preferences.linkOpening == .glance)
    reconcile(store.browserPullRequests)
    startPreloading()
  }

  func setPreloadingEnabled(_ enabled: Bool) {
    preloadingEnabled = enabled
    if !enabled {
      preloadTask?.cancel()
      preloadTask = nil
      pending.removeAll()
      for id in Array(pages.keys) where pages[id]?.hasBeenShown == false {
        pages.removeValue(forKey: id)?.discard()
      }
    }
  }

  func reconcile(_ pullRequests: [PullRequest]) {
    var seen: Set<String> = []
    let unique = pullRequests.filter { seen.insert($0.id).inserted }
    desiredPullRequests = unique
    let activeIDs = Set(unique.map(\.id))
    for id in Array(pages.keys) where !activeIDs.contains(id) {
      pages.removeValue(forKey: id)?.discard()
    }
    for pr in unique { pages[pr.id]?.update(pr) }
    pending = preloadingEnabled && !resettingSession ? unique.filter { pages[$0.id] == nil } : []
  }

  func open(_ pullRequest: PullRequest) {
    guard !resettingSession else { return }
    let page = pages[pullRequest.id] ?? makePage(pullRequest)
    pages[pullRequest.id] = page
    pending.removeAll { $0.id == pullRequest.id }
    page.update(pullRequest)
    page.show()
  }

  @discardableResult
  func preloadNext() -> Bool {
    guard preloadingEnabled, !resettingSession, !pending.isEmpty else { return false }
    let pr = pending.removeFirst()
    if pages[pr.id] == nil { pages[pr.id] = makePage(pr) }
    return true
  }

  private func startPreloading() {
    guard preloadingEnabled, !resettingSession, preloadTask == nil, !pending.isEmpty else { return }
    preloadTask = Task { [weak self] in
      while !Task.isCancelled {
        // Stagger creation without capping retained pages. A click bypasses this queue.
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        guard let self else { return }
        if !preloadNext() { preloadTask = nil; return }
      }
    }
  }

  func openLink(_ url: URL) {
    guard !resettingSession else { return }
    if let page = linkPages[url] { page.show(); return }
    let page = PullRequestBrowserWindow(url: url, title: "GitHub link", dataStore: webSession.dataStore,
      retainsWhenClosed: false, onDiscard: { [weak self] in self?.linkPages.removeValue(forKey: url) })
    linkPages[url] = page
    page.show()
  }

  func showSignIn() {
    guard !resettingSession else { return }
    if signInPage == nil {
      signInPage = PullRequestBrowserWindow(url: URL(string: "https://github.com/login")!,
        title: "Sign in to GitHub", windowTitle: "GitHub Sign-in — Glance", dataStore: webSession.dataStore)
    }
    signInPage?.show()
  }

  func signOut() async {
    guard !resettingSession else { return }
    resettingSession = true
    preloadTask?.cancel()
    preloadTask = nil
    pending.removeAll()
    discardAllPages()
    await webSession.signOut()
    resettingSession = false
    reconcile(desiredPullRequests)
    startPreloading()
  }

  private func discardAllPages() {
    for page in pages.values { page.discard() }
    pages.removeAll()
    for page in Array(linkPages.values) { page.discard() }
    linkPages.removeAll()
    signInPage?.discard()
    signInPage = nil
  }

  func shutDown() {
    subscription = nil
    preloadTask?.cancel()
    preloadTask = nil
    authenticationSubscription = nil
    discardAllPages()
    pending.removeAll()
  }
}
