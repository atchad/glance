import AppKit
import WebKit
@testable import Glance

enum BrowserFixtures {
  static func pullRequest(_ number: Int, title: String = "Fixture PR", head: String = "abc123") -> PullRequest {
    PullRequest(
      id: "PR_browser_\(number)", number: number, repository: "owner/repo", title: title, author: "fixture",
      authorAvatarURL: nil, url: URL(string: "https://github.com/owner/repo/pull/\(number)")!,
      branch: "feature", headRefOID: head, createdAt: .now, reviewRequestedAt: nil,
      updatedAt: .now, isDraft: false, reviewDecision: nil, checksState: .success,
      additions: 1, deletions: 0, labels: [], requestedReviewers: [], viewerReviewState: nil,
      viewerReviewedHeadOID: nil, viewerReviewSubmittedAt: nil,
      hasCurrentApprovalFromOtherReviewer: false, stackPosition: nil, stackSize: nil,
      viewerDidAuthor: false, mergeState: nil, unresolvedConversationCount: 0, checks: nil,
      autoMergeEnabled: false, mergeQueuePosition: nil, lifecycleState: .open,
      viewerReviewRequested: false)
  }
}

/// Offline native check: exercises actual WebKit state, not a simulated scroll offset.
@MainActor
enum PullRequestBrowserChecks {
  private struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  static func run() throws -> Int {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    if !NSApp.isRunning { NSApp.finishLaunching() }
    let page = PullRequestBrowserWindow(pullRequest: BrowserFixtures.pullRequest(1),
      dataStore: .nonPersistent(), loadPage: false)
    defer { page.discard() }
    var checks = 0
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
      checks += 1
      guard try condition() else { throw Failure(message: message) }
    }
    let html = """
      <!doctype html><html><body style="margin:0;height:5000px">
      <textarea id="draft">initial</textarea><details id="thread"><summary>Thread</summary>Discussion</details>
      <script>window.instanceID = Math.random().toString();</script></body></html>
      """
    page.webView.loadHTMLString(html, baseURL: URL(string: "https://github.com"))
    try wait { !page.webView.isLoading && page.webView.url != nil }
    // didFinish and DOM readiness can trail isLoading's KVO delivery.
    var ready = false
    try wait {
      page.webView.evaluateJavaScript("!!document.getElementById('draft')") { value, _ in ready = value as? Bool == true }
      return ready
    }
    try check(!page.window.isVisible && !page.hasBeenShown, "Preloading must not show a window or mark the page opened.")
    let window = page.window!
    let webView = page.webView
    page.show()
    pump()
    let originalFrame = window.frame
    try check(window.contentRect(forFrameRect: originalFrame).width >= 1000,
      "The browser must retain its intended desktop viewport after hosting attachment.")
    _ = try evaluate("document.getElementById('draft').value = 'Unfinished review 🐙'; document.getElementById('draft').focus(); document.getElementById('thread').open = true; window.scrollTo(0, 1400); history.pushState({}, '', '/owner/repo/pull/1/files');", in: webView)
    pump()
    let instance = try evaluate("window.instanceID", in: webView) as? String
    let scroll = try evaluate("window.scrollY", in: webView) as? Double
    try check((scroll ?? 0) > 1000, "The fixture must actually scroll before closing.")
    window.performClose(nil)
    pump()
    try check(!window.isVisible, "The close button must hide the window.")
    try check(page.webView === webView && page.window === window, "Closing must retain the same window and WebKit page.")
    page.update(BrowserFixtures.pullRequest(1, title: "Updated metadata", head: "changed"))
    page.reloadUnopenedPage()
    page.show()
    pump()
    try check(window.isVisible && window.frame == originalFrame, "Reopening must restore the same window and frame.")
    try check(try evaluate("window.instanceID", in: webView) as? String == instance, "Reopening or metadata changes must not reload the document.")
    try check(try evaluate("document.getElementById('draft').value", in: webView) as? String == "Unfinished review 🐙", "The unfinished comment must survive close/reopen and authentication refresh attempts.")
    try check(try evaluate("document.activeElement.id", in: webView) as? String == "draft", "Reopening must preserve the focused comment editor.")
    try check(try evaluate("document.getElementById('thread').open", in: webView) as? Bool == true, "Expanded thread state must survive.")
    try check(try evaluate("window.scrollY", in: webView) as? Double == scroll, "The exact scroll position must survive.")
    try check(webView.url?.path == "/owner/repo/pull/1/files", "The current PR subpage must survive.")
    let closeKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
      timestamp: 0, windowNumber: window.windowNumber, context: nil,
      characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
    try check(window.performKeyEquivalent(with: closeKey), "Command–W must be handled by the PR window, not the dashboard.")
    pump()
    try check(!window.isVisible, "Command–W must hide the retained page.")
    page.show()
    pump()
    page.webViewWebContentProcessDidTerminate(webView)
    try check(page.message != nil, "A terminated process must show an explicit recovery message.")
    try check(try evaluate("window.instanceID", in: webView) as? String == instance, "Process-termination handling must not silently reload.")
    let reloadKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
      timestamp: 0, windowNumber: window.windowNumber, context: nil,
      characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15)!
    try check(window.performKeyEquivalent(with: reloadKey), "Command–R must request the guarded browser reload.")
    pump()
    try check(window.attachedSheet != nil, "Explicit reload must warn about unfinished work.")
    if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
    pump()
    try check(try evaluate("document.getElementById('draft').value", in: webView) as? String == "Unfinished review 🐙", "Canceling reload must preserve the draft.")
    page.discard()
    try check(page.isDiscarded && !window.isVisible, "Discarding a removed PR must close its window.")
    try check(window.contentViewController == nil && window.contentView == nil
      && webView.navigationDelegate == nil && webView.uiDelegate == nil,
      "Discarding must detach the hosted page and delegates, breaking retention cycles.")
    page.show()
    try check(!window.isVisible, "A discarded page cannot reopen.")
    var isReleased: () -> Bool = { false }
    autoreleasepool {
      let disposable = PullRequestBrowserWindow(
        pullRequest: BrowserFixtures.pullRequest(2), dataStore: .nonPersistent(), loadPage: false)
      isReleased = { [weak releasedPage = disposable, weak releasedWebView = disposable.webView] in
        releasedPage == nil && releasedWebView == nil
      }
      disposable.discard()
    }
    try wait(isReleased, message: "Discarding did not release the page and WebKit view.")
    try check(isReleased(), "Cleanup must actually release the page and web view.")
    return checks
  }

  private static func evaluate(_ script: String, in webView: WKWebView) throws -> Any? {
    var result: Result<Any?, Error>?
    webView.evaluateJavaScript(script) { value, error in
      result = error.map { .failure($0) } ?? .success(value)
    }
    try wait { result != nil }
    return try result!.get()
  }

  private static func wait(_ condition: () throws -> Bool, message: String = "Timed out waiting for the offline WebKit fixture.") throws {
    let deadline = Date().addingTimeInterval(15)
    while try !condition() {
      guard Date() < deadline else { throw Failure(message: message) }
      pump()
    }
  }

  private static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
}
