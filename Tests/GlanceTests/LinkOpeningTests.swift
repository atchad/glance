import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Glance

@MainActor
final class LinkOpeningTests: XCTestCase {
  private let link = URL(string: "https://github.com/owner/repo/pull/1")!
  private let application = LinkApplication(url: URL(fileURLWithPath: "/Applications/Fixture Browser.app"),
    bundleIdentifier: "test.fixture.browser")

  func testPreferencesDefaultToSystemBrowserAndRoundTripEveryDestination() throws {
    XCTAssertEqual(Preferences().linkOpening, .defaultBrowser)
    XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).linkOpening, .defaultBrowser)
    for choice in [LinkOpeningPreference.glance, .defaultBrowser, .application(application)] {
      var preferences = Preferences.default
      preferences.linkOpening = choice
      let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
      XCTAssertEqual(restored.linkOpening, choice)
      XCTAssertFalse(restored.recoveredInvalidValues)
    }
    let glance = LinkApplication(url: URL(fileURLWithPath: "/Applications/Glance-preview.app"),
      bundleIdentifier: "app.glance.Glance")
    var preferences = Preferences.default
    preferences.linkOpening = .application(glance)
    XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)).linkOpening, .glance)
  }

  func testInvalidDestinationRecoversWithoutDiscardingOtherPreferences() throws {
    for invalid in ["null", "123", "{\"unknown\":{}}",
      "{\"application\":{\"_0\":{\"url\":\"https://example.com/browser.app\"}}}"]
    {
      let data = Data("{\"linkOpening\":\(invalid),\"showAuthor\":false}".utf8)
      let preferences = try JSONDecoder().decode(Preferences.self, from: data)
      XCTAssertEqual(preferences.linkOpening, .defaultBrowser)
      XCTAssertTrue(preferences.recoveredInvalidValues)
      XCTAssertFalse(preferences.showAuthor)
    }
  }

  func testSelectedApplicationAndFallbackNeverChangeTheSystemDefault() async {
    var defaultLinks: [URL] = []
    var applicationLinks: [(URL, URL)] = []
    var isInstalled = true
    var failsToLaunch = false
    let opener = ExternalLinkOpener(resolve: { app in isInstalled ? app.url : nil },
      openDefault: { defaultLinks.append($0); return true },
      openApplication: { url, app in
        if failsToLaunch { throw CocoaError(.executableLoad) }
        applicationLinks.append((url, app))
      })
    let firstWarning = await opener.open(link, preference: .application(application))
    XCTAssertNil(firstWarning)
    XCTAssertEqual(applicationLinks.first?.0, link)
    XCTAssertEqual(applicationLinks.first?.1, application.url)
    XCTAssertTrue(defaultLinks.isEmpty)
    isInstalled = false
    let missingWarning = await opener.open(link, preference: .application(application))
    XCTAssertTrue(missingWarning?.contains("no longer available") == true)
    XCTAssertEqual(defaultLinks, [link])
    isInstalled = true
    failsToLaunch = true
    let launchWarning = await opener.open(link, preference: .application(application))
    XCTAssertTrue(launchWarning?.contains("default browser instead") == true)
    XCTAssertEqual(defaultLinks, [link, link])
    let defaultWarning = await opener.open(link, preference: .defaultBrowser)
    XCTAssertNil(defaultWarning)
    XCTAssertEqual(defaultLinks, [link, link, link])
    let brokenDefault = ExternalLinkOpener(resolve: { _ in nil }, openDefault: { _ in false })
    let failure = await brokenDefault.open(link, preference: .application(application))
    XCTAssertTrue(failure?.contains("also couldn’t open") == true)
  }

  func testNativePickerOrderCancellationAndCustomApplicationSelection() {
    _ = NSApplication.shared
    var choice: LinkOpeningPreference = .glance
    let coordinator = LinkApplicationPicker.Coordinator()
    coordinator.selection = Binding(get: { choice }, set: { choice = $0 })
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    let recommended = LinkApplication(url: URL(fileURLWithPath: "/Applications/Recommended.app"))
    coordinator.update(popup, applications: [recommended], selection: choice)
    XCTAssertEqual(popup.itemArray.filter { !$0.isSeparatorItem }.map(\.title),
      ["Default browser", "Glance", "Recommended", "Choose application…"])
    coordinator.chooseApplication = { _, completion in completion(nil) }
    popup.selectItem(withTag: -1)
    coordinator.selected(popup)
    XCTAssertEqual(choice, .glance)
    XCTAssertEqual(popup.selectedItem?.title, "Glance")
    coordinator.chooseApplication = { [application] _, completion in completion(application) }
    popup.selectItem(withTag: -1)
    coordinator.selected(popup)
    XCTAssertEqual(choice, .application(application))
    XCTAssertEqual(popup.selectedItem?.title, "Fixture Browser")
    coordinator.update(popup, applications: [recommended], selection: choice)
    XCTAssertEqual(popup.selectedItem?.title, "Fixture Browser", "The chosen app must remain listed after reopening Settings")
    let glance = LinkApplication(url: URL(fileURLWithPath: "/Applications/Glance.app"), bundleIdentifier: "app.glance.Glance")
    coordinator.chooseApplication = { _, completion in completion(glance) }
    popup.selectItem(withTag: -1)
    coordinator.selected(popup)
    XCTAssertEqual(choice, .glance, "Choosing another Glance bundle must use its internal browser, not recursively launch Glance")
    popup.selectItem(withTag: 0)
    coordinator.selected(popup)
    XCTAssertEqual(choice, .defaultBrowser)
  }

  func testRecommendationsComeFromValidOSHandlersAndAreDeduplicated() {
    let a = URL(fileURLWithPath: "/Applications/Alpha.app")
    let z = URL(fileURLWithPath: "/Applications/Zeta.app")
    let recommendations = LinkApplications.recommendations([z, a, a, URL(string: "https://example.com")!])
    XCTAssertEqual(recommendations.map(\.url), [a, z])
    XCTAssertTrue(LinkApplications.recommended().allSatisfy { $0.isValid && !$0.isGlance })
  }

  func testHostedNativeDropdownDispatchesSelectionThroughItsRealTarget() async {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    let browser = PullRequestBrowser(dataStore: .nonPersistent()) { _ in RoutingBrowserPage() }
    store.enablePullRequestBrowser(browser)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = NSHostingController(rootView:
      Form { LinkOpeningSettingsView(store: store, session: browser.webSession) }.formStyle(.grouped))
    defer {
      window.contentViewController = nil
      window.contentView = nil
      window.close()
      browser.shutDown()
    }
    window.contentView?.layoutSubtreeIfNeeded()
    await waitUntil { self.findPopup(in: window.contentView) != nil }
    guard let popup = findPopup(in: window.contentView), let action = popup.action else {
      XCTFail("Settings must host an actionable native application dropdown")
      return
    }
    XCTAssertEqual(popup.selectedItem?.title, "Default browser")
    popup.selectItem(withTag: 0)
    XCTAssertTrue(popup.sendAction(action, to: popup.target))
    XCTAssertEqual(store.preferences.linkOpening, .defaultBrowser)
    popup.selectItem(withTag: 1)
    XCTAssertTrue(popup.sendAction(action, to: popup.target))
    XCTAssertEqual(store.preferences.linkOpening, .glance)
  }

  private func findPopup(in view: NSView?) -> NSPopUpButton? {
    if let popup = view as? NSPopUpButton { return popup }
    for child in view?.subviews ?? [] {
      if let popup = findPopup(in: child) { return popup }
    }
    return nil
  }

  func testSwitchingDestinationRoutesClicksAndPreservesOpenedPages() async {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pr = BrowserFixtures.pullRequest(1)
    var defaultLinks: [URL] = []
    var applications: [URL] = []
    let opener = ExternalLinkOpener(resolve: { $0.url },
      openDefault: { defaultLinks.append($0); return true },
      openApplication: { _, application in applications.append(application) })
    let store = AppStore(storageDirectory: directory, externalLinkOpener: opener) { sections in
      ("fixture", sections.map { SectionSnapshot(id: $0.id, pullRequests: [pr]) })
    }
    store.preferences.linkOpening = .glance
    var pages: [RoutingBrowserPage] = []
    let browser = PullRequestBrowser(dataStore: .nonPersistent()) { _ in
      let page = RoutingBrowserPage()
      pages.append(page)
      return page
    }
    store.enablePullRequestBrowser(browser)
    defer { browser.shutDown() }
    store.refresh()
    await waitUntil { !store.isRefreshing && browser.pending.count == 1 }
    let commands = ApplicationCommands(store: store, updates: UpdateController(startingUpdater: false))
    XCTAssertTrue(commands.perform(.openPR, target: CommandTarget(pullRequest: pr)))
    XCTAssertEqual(pages.count, 1)
    store.preferences.linkOpening = .defaultBrowser
    await waitUntil { browser.pending.isEmpty }
    store.open(pr)
    await waitUntil { defaultLinks == [pr.url] }
    XCTAssertEqual(pages[0].discards, 0)
    XCTAssertEqual(pages[0].shows, 1)
    store.preferences.linkOpening = .application(application)
    store.openLink(link)
    await waitUntil { applications == [application.url] }
    store.preferences.linkOpening = .glance
    store.open(pr)
    XCTAssertEqual(pages.count, 1)
    XCTAssertEqual(pages[0].shows, 2)
  }

  func testExternalModeNeverPreloadsAndDiscardOnlyUnopenedPagesOnSwitch() {
    let opened = RoutingBrowserPage()
    let unopened = RoutingBrowserPage()
    let browser = PullRequestBrowser(dataStore: .nonPersistent()) { pr in pr.number == 1 ? opened : unopened }
    defer { browser.shutDown() }
    let prs = [BrowserFixtures.pullRequest(1), BrowserFixtures.pullRequest(2)]
    browser.reconcile(prs)
    browser.open(prs[0])
    browser.preloadNext()
    browser.setPreloadingEnabled(false)
    browser.reconcile(prs)
    XCTAssertTrue(browser.pending.isEmpty)
    XCTAssertFalse(browser.preloadNext())
    XCTAssertEqual(opened.discards, 0)
    XCTAssertEqual(unopened.discards, 1)
    browser.setPreloadingEnabled(true)
    browser.reconcile(prs)
    XCTAssertEqual(browser.pending.map(\.id), [prs[1].id])
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<300 {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for link routing")
  }
}

@MainActor
private final class RoutingBrowserPage: PullRequestBrowserPage {
  var hasBeenShown = false
  var shows = 0
  var discards = 0
  func update(_ pullRequest: PullRequest) {}
  func show() { hasBeenShown = true; shows += 1 }
  func discard() { discards += 1 }
  func reloadUnopenedPage() {}
}
