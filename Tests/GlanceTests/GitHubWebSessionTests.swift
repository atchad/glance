import WebKit
import XCTest
@testable import Glance

@MainActor
final class GitHubWebSessionTests: XCTestCase {
  func testSessionDetectionRequiresUnexpiredGitHubLoginAndSessionCookies() {
    let loggedIn = cookie("logged_in", "yes")
    let session = cookie("user_session", "fixture-not-a-real-token")
    XCTAssertEqual(GitHubWebSession.state(for: []), .signedOut)
    XCTAssertEqual(GitHubWebSession.state(for: [loggedIn]), .signedOut)
    XCTAssertEqual(GitHubWebSession.state(for: [session]), .signedOut)
    XCTAssertEqual(GitHubWebSession.state(for: [loggedIn, session]), .signedIn(nil))
    XCTAssertEqual(GitHubWebSession.state(for: [loggedIn, session, cookie("dotcom_user", "fixture")]), .signedIn("fixture"))
    XCTAssertEqual(GitHubWebSession.state(for: [loggedIn, cookie("user_session", "expired", expires: .distantPast)]), .signedOut)
    XCTAssertEqual(GitHubWebSession.state(for: [loggedIn, cookie("user_session", "evil", domain: "github.com.evil.example")]), .signedOut)
    XCTAssertEqual(GitHubWebSession.state(for: [cookie("logged_in", "no"), session]), .signedOut)
    XCTAssertEqual(GitHubWebSession.state(for: [loggedIn, cookie("__Host-user_session_same_site", "fixture")]), .signedIn(nil))
    XCTAssertFalse(GitHubWebSession.State.checking.isLoggedIn)
    XCTAssertTrue(GitHubWebSession.State.signedIn(nil).isLoggedIn)
  }

  func testLiveCookieChangesUpdateLoginStateAndSignOutPreservesOtherSites() async {
    let dataStore = WKWebsiteDataStore.nonPersistent()
    let session = GitHubWebSession(dataStore: dataStore)
    await waitUntil { session.state == .signedOut }
    await dataStore.httpCookieStore.setCookie(cookie("logged_in", "yes"))
    await dataStore.httpCookieStore.setCookie(cookie("user_session", "fixture-not-a-real-token"))
    await dataStore.httpCookieStore.setCookie(cookie("dotcom_user", "fixture"))
    let unrelated = cookie("other_session", "retain-me", domain: "identity.example.com")
    await dataStore.httpCookieStore.setCookie(unrelated)
    session.refresh()
    await waitUntil { session.state == .signedIn("fixture") }
    XCTAssertGreaterThan(session.authenticationRevision, 0)
    await session.signOut()
    await waitUntil { session.state == .signedOut }
    let retained = await dataStore.httpCookieStore.allCookies()
    XCTAssertFalse(retained.contains { GitHubWebSession.isGitHubDomain($0.domain) })
    XCTAssertTrue(retained.contains { $0.name == unrelated.name && $0.value == unrelated.value })
    XCTAssertFalse(session.isSigningOut)
  }

  func testBrowserSignOutDiscardsOpenedAndPreloadedPagesBeforeClearingSession() async {
    var discarded = 0
    let browser = PullRequestBrowser(dataStore: .nonPersistent()) { _ in
      LogoutBrowserPage { discarded += 1 }
    }
    defer { browser.shutDown() }
    let prs = [BrowserFixtures.pullRequest(1), BrowserFixtures.pullRequest(2)]
    browser.reconcile(prs)
    browser.open(prs[0])
    browser.preloadNext()
    await browser.signOut()
    XCTAssertEqual(discarded, 2)
    XCTAssertTrue(browser.pages.isEmpty)
    XCTAssertEqual(browser.pending.count, 2)
  }

  func testLogOutDoesNotAllowAConcurrentClickToCreateAnAuthenticatedPage() async {
    var browser: PullRequestBrowser?
    var created = 0
    browser = PullRequestBrowser(dataStore: .nonPersistent()) { _ in
      created += 1
      return LogoutBrowserPage {
        browser?.open(BrowserFixtures.pullRequest(2))
      }
    }
    defer { browser?.shutDown(); browser = nil }
    browser?.open(BrowserFixtures.pullRequest(1))
    await browser?.signOut()
    XCTAssertEqual(created, 1, "New pages must be blocked while the website session is being cleared")
    XCTAssertTrue(browser?.pages.isEmpty == true)
  }

  private func cookie(_ name: String, _ value: String, domain: String = "github.com", expires: Date? = nil) -> HTTPCookie {
    var properties: [HTTPCookiePropertyKey: Any] = [.domain: domain, .path: "/", .name: name, .value: value, .secure: "TRUE"]
    if let expires { properties[.expires] = expires }
    return HTTPCookie(properties: properties)!
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<300 {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for the offline WebKit cookie store")
  }
}

@MainActor
private final class LogoutBrowserPage: PullRequestBrowserPage {
  var hasBeenShown = false
  let didDiscard: () -> Void
  init(_ didDiscard: @escaping () -> Void) { self.didDiscard = didDiscard }
  func update(_ pullRequest: PullRequest) {}
  func show() { hasBeenShown = true }
  func discard() { didDiscard() }
  func reloadUnopenedPage() {}
}
