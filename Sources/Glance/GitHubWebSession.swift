import AppKit
import WebKit

/// Website authentication, not GitHub API authentication. Never inject CLI/OAuth tokens
/// into GitHub pages. Cookie presence is a local session indicator, not a server check.
@MainActor
final class GitHubWebSession: NSObject, ObservableObject, WKHTTPCookieStoreObserver {
  enum State: Equatable {
    case checking
    case signedOut
    case signedIn(String?)

    var isLoggedIn: Bool {
      if case .signedIn = self { return true }
      return false
    }
  }

  @Published private(set) var state: State = .checking
  @Published private(set) var isSigningOut = false
  @Published private(set) var authenticationRevision = 0
  let dataStore: WKWebsiteDataStore
  private var authenticationCookies: [String: String]?
  private var readGeneration = 0
  private var activationObserver: NSObjectProtocol?

  init(dataStore: WKWebsiteDataStore? = nil) {
    self.dataStore = dataStore ?? .default()
    super.init()
    self.dataStore.httpCookieStore.add(self)
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    refresh()
  }

  deinit {
    if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
  }

  nonisolated static func isGitHubDomain(_ domain: String) -> Bool {
    let normalized = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return normalized == "github.com" || normalized.hasSuffix(".github.com")
  }

  nonisolated static func state(for cookies: [HTTPCookie], now: Date = Date()) -> State {
    let active = cookies.filter {
      isGitHubDomain($0.domain) && !$0.value.isEmpty && ($0.expiresDate.map { $0 > now } ?? true)
    }
    let loggedIn = active.contains { $0.name == "logged_in" && $0.value == "yes" }
    let hasSession = active.contains { ["user_session", "__Host-user_session_same_site"].contains($0.name) }
    guard loggedIn && hasSession else { return .signedOut }
    return .signedIn(active.first { $0.name == "dotcom_user" }?.value)
  }

  func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { refresh() }

  func refresh() {
    readGeneration += 1
    let generation = readGeneration
    dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
      guard let self, generation == self.readGeneration else { return }
      self.state = Self.state(for: cookies)
      let signature = Dictionary(cookies.filter {
        Self.isGitHubDomain($0.domain)
          && ["user_session", "__Host-user_session_same_site", "logged_in", "dotcom_user"].contains($0.name)
      }.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
      let previous = self.authenticationCookies
      self.authenticationCookies = signature
      if let previous, previous != signature { self.authenticationRevision += 1 }
    }
  }

  func signOut() async {
    guard !isSigningOut else { return }
    isSigningOut = true
    defer { isSigningOut = false }
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    let records = await dataStore.dataRecords(ofTypes: types)
    let githubRecords = records.filter { Self.isGitHubDomain($0.displayName) }
    await dataStore.removeData(ofTypes: types, for: githubRecords)
    // Include session/HTTP-only cookies explicitly, even if a WebKit version omitted
    // them from its website-data records. Other websites' and browsers' data stays intact.
    let cookies = await dataStore.httpCookieStore.allCookies()
    for cookie in cookies where Self.isGitHubDomain(cookie.domain) {
      await dataStore.httpCookieStore.deleteCookie(cookie)
    }
    refresh()
  }
}
