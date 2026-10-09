import XCTest
import WebKit
@testable import Glance

@MainActor
final class PullRequestBrowserTests: XCTestCase {
  func testPreloadsEveryUniquePRWithoutOpeningWindowsOrLimitingCount() {
    var created: [FakeBrowserPage] = []
    let browser = PullRequestBrowser(dataStore: .nonPersistent()) { pr in
      let page = FakeBrowserPage(pr)
      created.append(page)
      return page
    }
    defer { browser.shutDown() }
    let prs = (1...20).map { BrowserFixtures.pullRequest($0) }
    browser.reconcile(prs + [prs[0]])
    XCTAssertEqual(browser.pending.count, 20)
    while browser.preloadNext() {}
    XCTAssertEqual(created.count, 20)
    XCTAssertEqual(browser.pages.count, 20)
    XCTAssertTrue(created.allSatisfy { $0.shows == 0 })
    browser.reconcile(prs.reversed())
    XCTAssertFalse(browser.preloadNext())
    XCTAssertEqual(created.count, 20)
  }

  func testOpeningPendingPRBypassesQueueAndReusesPageOnEveryOpen() {
    var created: [FakeBrowserPage] = []
    let browser = PullRequestBrowser(dataStore: .nonPersistent()) { pr in
      let page = FakeBrowserPage(pr)
      created.append(page)
      return page
    }
    defer { browser.shutDown() }
    let first = BrowserFixtures.pullRequest(1)
    let second = BrowserFixtures.pullRequest(2)
    browser.reconcile([first, second])
    browser.open(second)
    browser.open(second)
    XCTAssertEqual(created.count, 1)
    XCTAssertEqual(created[0].shows, 2)
    XCTAssertEqual(browser.pending.map(\.id), [first.id])
    XCTAssertTrue(browser.preloadNext())
    XCTAssertFalse(browser.preloadNext())
    XCTAssertEqual(created.count, 2)
  }

  func testRemovingOpenedPagesDiscardsThemAndCancelsPendingPreloads() {
    var created: [FakeBrowserPage] = []
    let browser = PullRequestBrowser(dataStore: .nonPersistent()) { pr in
      let page = FakeBrowserPage(pr)
      created.append(page)
      return page
    }
    let first = BrowserFixtures.pullRequest(1)
    let second = BrowserFixtures.pullRequest(2)
    browser.reconcile([first, second])
    browser.open(first)
    browser.reconcile([])
    XCTAssertEqual(created[0].discards, 1)
    XCTAssertTrue(browser.pages.isEmpty)
    XCTAssertFalse(browser.preloadNext())
    browser.reconcile([first])
    browser.open(first)
    XCTAssertEqual(created.count, 2, "A PR returning to the queue gets a new page")
    browser.shutDown()
    XCTAssertEqual(created[1].discards, 1)
    XCTAssertTrue(browser.pages.isEmpty)
  }

  func testMetadataChangesUpdateWithoutRecreatingLivePage() {
    let first = BrowserFixtures.pullRequest(1)
    let page = FakeBrowserPage(first)
    let browser = PullRequestBrowser(dataStore: .nonPersistent()) { _ in page }
    defer { browser.shutDown() }
    browser.reconcile([first])
    browser.preloadNext()
    let changed = BrowserFixtures.pullRequest(1, title: "New title", head: "new-commit")
    browser.reconcile([changed])
    XCTAssertTrue(browser.pages[first.id] === page)
    XCTAssertEqual(page.pullRequest.title, "New title")
    XCTAssertEqual(page.pullRequest.headRefOID, "new-commit")
    XCTAssertEqual(page.discards, 0)
    XCTAssertEqual(page.reloads, 0)
  }

  func testNavigationSeparatesExternalLinksAuthenticationAndUnsafeSchemes() {
    typealias Policy = PullRequestBrowserNavigation
    func destination(_ url: String, user: Bool = true, new: Bool = false) -> Policy.Destination {
      Policy.destination(for: URL(string: url)!, userInitiated: user, newWindow: new)
    }
    XCTAssertEqual(destination("https://github.com/owner/repo/pull/1/files"), .embedded)
    XCTAssertEqual(destination("https://github.com/login", user: false), .embedded)
    XCTAssertEqual(destination("https://sso.example.com/login", user: false), .embedded)
    XCTAssertEqual(destination("https://sso.example.com/login"), .external)
    XCTAssertEqual(destination("https://github.com.evil.example/path"), .external)
    XCTAssertEqual(destination("https://github.com/path", new: true), .external)
    XCTAssertEqual(destination("https://example.com", user: false, new: true), .blocked)
    XCTAssertEqual(destination("http://github.com/login", user: false), .blocked)
    XCTAssertEqual(destination("mailto:owner@example.com"), .external)
    for url in ["file:///etc/passwd", "javascript:alert(1)", "data:text/html,hello", "custom:launch"] {
      XCTAssertEqual(destination(url), .blocked)
    }
  }

  func testStoreMembershipSurvivesDuplicateSectionsSnoozingAndFailedRefreshes() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pr = BrowserFixtures.pullRequest(1)
    var failed = false
    var rows = [pr]
    let store = AppStore(storageDirectory: directory) { sections in
      if failed { throw GitHubError.api("Offline fixture") }
      return ("fixture", sections.map { SectionSnapshot(id: $0.id, pullRequests: rows) })
    }
    var created: [FakeBrowserPage] = []
    let browser = PullRequestBrowser(dataStore: .nonPersistent()) { pr in
      let page = FakeBrowserPage(pr)
      created.append(page)
      return page
    }
    store.preferences.linkOpening = .glance
    browser.bind(to: store)
    defer { browser.shutDown() }
    store.refresh()
    await waitUntil { !store.isRefreshing && browser.pending.count == 1 }
    browser.preloadNext()
    XCTAssertEqual(store.browserPullRequests.map(\.id), [pr.id])
    store.preferences.sections.removeFirst()
    await settle()
    XCTAssertEqual(browser.pages.count, 1, "Removing one of two matching sections must retain the page")
    store.snooze(pr, condition: .until(Date().addingTimeInterval(3600)))
    await settle()
    XCTAssertTrue(browser.pages[pr.id] === created[0], "Snoozed PRs are still listed")
    failed = true
    store.refresh()
    await waitUntil { !store.isRefreshing }
    await settle()
    XCTAssertNotNil(store.errorMessage)
    XCTAssertEqual(created[0].discards, 0, "An offline refresh must not discard cached pages")
    failed = false
    rows = []
    store.refresh()
    await waitUntil { !store.isRefreshing && browser.pages.isEmpty }
    XCTAssertEqual(created[0].discards, 1, "A successful removal must discard even a snoozed page")
  }

  func testDismissalUndoAndRepositoryExclusionReconcileLivePages() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pr = BrowserFixtures.pullRequest(1)
    let store = AppStore(storageDirectory: directory) { sections in
      ("fixture", sections.map { SectionSnapshot(id: $0.id, pullRequests: [pr]) })
    }
    var created: [FakeBrowserPage] = []
    let browser = PullRequestBrowser(dataStore: .nonPersistent()) { pr in
      let page = FakeBrowserPage(pr)
      created.append(page)
      return page
    }
    store.preferences.linkOpening = .glance
    browser.bind(to: store)
    defer { browser.shutDown() }
    store.refresh()
    await waitUntil { !store.isRefreshing && browser.pending.count == 1 }
    browser.open(pr)
    store.dismiss(pr)
    await waitUntil { browser.pages.isEmpty }
    XCTAssertEqual(created[0].discards, 1)
    store.undoDismissal()
    await waitUntil { browser.pending.count == 1 }
    browser.preloadNext()
    XCTAssertEqual(created.count, 2)
    store.preferences.excludedRepositories = [pr.repository]
    await waitUntil { browser.pages.isEmpty }
    XCTAssertEqual(created[1].discards, 1)
    XCTAssertTrue(browser.pending.isEmpty)
  }

  func testAuthenticationChangesReloadOnlyNeverOpenedPreloads() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    let dataStore = WKWebsiteDataStore.nonPersistent()
    var created: [FakeBrowserPage] = []
    let browser = PullRequestBrowser(dataStore: dataStore) { pr in
      let page = FakeBrowserPage(pr)
      created.append(page)
      return page
    }
    store.preferences.linkOpening = .glance
    browser.bind(to: store)
    defer { browser.shutDown() }
    await settle()
    browser.reconcile([BrowserFixtures.pullRequest(1), BrowserFixtures.pullRequest(2)])
    browser.preloadNext()
    browser.preloadNext()
    browser.open(BrowserFixtures.pullRequest(2))
    let cookie = HTTPCookie(properties: [.domain: "github.com", .path: "/",
      .name: "logged_in", .value: "yes", .secure: "TRUE"])!
    await dataStore.httpCookieStore.setCookie(cookie)
    browser.webSession.refresh()
    await waitUntil { created[0].reloads > 0 }
    XCTAssertEqual(created[1].reloads, 0, "Already-opened pages must not reload when cookies change")
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<300 {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for browser reconciliation")
  }

  private func settle() async { try? await Task.sleep(for: .milliseconds(100)) }

  func testLiveWebViewRetainsDraftScrollHistoryAndWindowAcrossCloseAndReopen() throws {
    XCTAssertGreaterThan(try PullRequestBrowserChecks.run(), 0)
  }
}

@MainActor
private final class FakeBrowserPage: PullRequestBrowserPage {
  var pullRequest: PullRequest
  var hasBeenShown = false
  var shows = 0
  var discards = 0
  var reloads = 0
  init(_ pr: PullRequest) { pullRequest = pr }
  func update(_ pr: PullRequest) { pullRequest = pr }
  func show() { hasBeenShown = true; shows += 1 }
  func discard() { discards += 1 }
  func reloadUnopenedPage() { reloads += 1 }
}
