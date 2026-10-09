import AppKit
import SwiftUI
import WebKit

enum PullRequestBrowserNavigation {
  enum Destination: Equatable { case embedded, external, blocked }

  static func destination(for url: URL, userInitiated: Bool, newWindow: Bool) -> Destination {
    let scheme = url.scheme?.lowercased()
    if scheme == "https" || scheme == "http" {
      if newWindow { return userInitiated ? .external : .blocked }
      if userInitiated && url.host?.lowercased() != "github.com" { return .external }
      // Authentication redirects (including organization SSO) must use this cookie store.
      return scheme == "https" ? .embedded : .blocked
    }
    if userInitiated && scheme == "mailto" { return .external }
    return .blocked
  }
}

@MainActor
final class PullRequestBrowserWindow: NSObject, ObservableObject, PullRequestBrowserPage,
  NSWindowDelegate, WKNavigationDelegate, WKUIDelegate
{
  @Published private(set) var pageTitle: String
  @Published private(set) var canGoBack = false
  @Published private(set) var canGoForward = false
  @Published private(set) var isLoading = false
  @Published private(set) var currentURL: URL?
  @Published private(set) var message: String?
  private(set) var hasBeenShown = false
  private(set) var isDiscarded = false
  let webView: WKWebView
  private(set) var window: NSWindow!
  private var observations: [NSKeyValueObservation] = []
  fileprivate let originalURL: URL
  fileprivate let footer: String
  private let retainsWhenClosed: Bool
  private let onDiscard: (() -> Void)?

  convenience init(pullRequest: PullRequest, dataStore: WKWebsiteDataStore? = nil, loadPage: Bool = true) {
    self.init(url: pullRequest.url, title: pullRequest.title,
      windowTitle: "\(pullRequest.repository) #\(pullRequest.number) — Glance",
      footer: "Closing hides this page; removal from Glance discards it, including unfinished work.",
      dataStore: dataStore, loadPage: loadPage)
  }

  init(url: URL, title: String, windowTitle: String? = nil,
    footer: String = "This window shares Glance’s GitHub website sign-in. It does not use your GitHub CLI token.",
    dataStore: WKWebsiteDataStore? = nil, loadPage: Bool = true,
    retainsWhenClosed: Bool = true, onDiscard: (() -> Void)? = nil)
  {
    pageTitle = title
    originalURL = url
    self.footer = footer
    self.retainsWhenClosed = retainsWhenClosed
    self.onDiscard = onDiscard
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore ?? .default()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init()
    webView.navigationDelegate = self
    webView.uiDelegate = self
    // Keep the real view attached to a full-size window even while hidden, so a preload
    // uses the same viewport as the page the user eventually sees.
    let browserWindow = PersistentPRWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    browserWindow.reloadPage = { [weak self] in self?.requestReload() }
    window = browserWindow
    window.title = windowTitle ?? "\(title) — Glance"
    window.contentMinSize = NSSize(width: 640, height: 420)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.delegate = self
    window.contentViewController = NSHostingController(rootView: PullRequestBrowserContent(page: self))
    // Hosting attachment can shrink a native window to the SwiftUI view's minimum.
    // Establish the desktop viewport afterwards, before loading the page.
    window.setContentSize(NSSize(width: 1100, height: 800))
    window.center()
    window.contentView?.layoutSubtreeIfNeeded()
    observations = [
      observeNavigation(\.canGoBack), observeNavigation(\.canGoForward),
      observeNavigation(\.isLoading), observeNavigation(\.url),
    ]
    updateNavigationState()
    if loadPage { webView.load(URLRequest(url: originalURL)) }
  }

  private func observeNavigation<Value>(_ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
    webView.observe(keyPath, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async { self?.updateNavigationState() }
    }
  }

  private func updateNavigationState() {
    guard !isDiscarded else { return }
    canGoBack = webView.canGoBack
    canGoForward = webView.canGoForward
    isLoading = webView.isLoading
    currentURL = webView.url
  }

  func update(_ pullRequest: PullRequest) {
    guard !isDiscarded else { return }
    if pageTitle != pullRequest.title { pageTitle = pullRequest.title }
    window.title = "\(pullRequest.repository) #\(pullRequest.number) — Glance"
  }

  func show() {
    guard !isDiscarded else { return }
    hasBeenShown = true
    NSApp.activate(ignoringOtherApps: true)
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(webView)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if retainsWhenClosed { sender.orderOut(nil) }
    else { discard() }
    return false
  }

  func discard() {
    guard !isDiscarded else { return }
    isDiscarded = true
    observations.removeAll()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
    window.delegate = nil
    window.close()
    // Break window -> hosting view -> page ownership, and release WebKit's page.
    window.contentViewController = nil
    window.contentView = nil
    onDiscard?()
  }

  func reloadUnopenedPage() {
    guard !isDiscarded, !hasBeenShown else { return }
    webView.load(URLRequest(url: originalURL))
  }

  func requestReload() {
    guard !isDiscarded, window.attachedSheet == nil else { return }
    let alert = NSAlert()
    alert.messageText = "Reload this GitHub page?"
    alert.informativeText = "Reloading can lose unfinished comments, review edits, expanded sections, and your scroll position. Closing and reopening this window does not reload it."
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Reload")
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertSecondButtonReturn, let self, !self.isDiscarded else { return }
      self.message = nil
      if self.webView.url == nil { self.webView.load(URLRequest(url: self.originalURL)) }
      else { self.webView.reload() }
    }
  }

  func openInDefaultBrowser() { NSWorkspace.shared.open(currentURL ?? originalURL) }
  func goBack() { webView.goBack() }
  func goForward() { webView.goForward() }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
  {
    guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
    // Subframes cannot launch external apps and may need non-HTTP resource URLs.
    if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
    let destination = PullRequestBrowserNavigation.destination(for: url,
      userInitiated: navigationAction.navigationType == .linkActivated,
      newWindow: navigationAction.targetFrame == nil)
    switch destination {
    case .embedded: decisionHandler(.allow)
    case .external: NSWorkspace.shared.open(url); decisionHandler(.cancel)
    case .blocked: decisionHandler(.cancel)
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void)
  {
    guard navigationResponse.canShowMIMEType else {
      if navigationResponse.isForMainFrame, let url = navigationResponse.response.url,
        ["https", "http"].contains(url.scheme?.lowercased() ?? "")
      { NSWorkspace.shared.open(url) }
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { message = nil }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    showLoadError(error)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    showLoadError(error)
  }

  private func showLoadError(_ error: Error) {
    guard (error as NSError).code != NSURLErrorCancelled else { return }
    message = "Couldn’t load the page: \(error.localizedDescription) Use Reload to try again, or open it in your default browser."
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    message = "WebKit stopped this page. Its live state may have been lost. Use Reload to recover; Glance will not reload it automatically."
  }

  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void)
  {
    let alert = scriptAlert(message: message, frame: frame)
    alert.addButton(withTitle: "OK")
    guard window.isVisible, window.attachedSheet == nil else { completionHandler(); return }
    alert.beginSheetModal(for: window) { _ in completionHandler() }
  }

  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void)
  {
    let alert = scriptAlert(message: message, frame: frame)
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "OK")
    guard window.isVisible, window.attachedSheet == nil else { completionHandler(false); return }
    alert.beginSheetModal(for: window) { completionHandler($0 == .alertSecondButtonReturn) }
  }

  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?, initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (String?) -> Void)
  {
    let alert = scriptAlert(message: prompt, frame: frame)
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "OK")
    let field = NSTextField(string: defaultText ?? "")
    field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
    alert.accessoryView = field
    guard window.isVisible, window.attachedSheet == nil else { completionHandler(nil); return }
    alert.beginSheetModal(for: window) { completionHandler($0 == .alertSecondButtonReturn ? field.stringValue : nil) }
  }

  private func scriptAlert(message: String, frame: WKFrameInfo) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = frame.securityOrigin.host
    alert.informativeText = message
    return alert
  }

  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void)
  {
    guard window.isVisible, window.attachedSheet == nil else { completionHandler(nil); return }
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection
    panel.canChooseDirectories = parameters.allowsDirectories
    panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
  }
}

/// Keep browser shortcuts window-scoped, ahead of WebKit and the app's dashboard menus.
private final class PersistentPRWindow: NSWindow {
  var reloadPage: (() -> Void)?

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    if attachedSheet == nil, modifiers == .command {
      switch event.charactersIgnoringModifiers?.lowercased() {
      case "w": performClose(nil); return true
      case "r": reloadPage?(); return true
      default: break
      }
    }
    return super.performKeyEquivalent(with: event)
  }
}

private struct PullRequestBrowserContent: View {
  @ObservedObject var page: PullRequestBrowserWindow

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Button(action: page.goBack) { Image(systemName: "chevron.left") }
          .disabled(!page.canGoBack).help("Back").accessibilityLabel("Back")
        Button(action: page.goForward) { Image(systemName: "chevron.right") }
          .disabled(!page.canGoForward).help("Forward").accessibilityLabel("Forward")
        Button(action: page.requestReload) { Image(systemName: "arrow.clockwise") }
          .help("Reload… Unfinished work may be lost").accessibilityLabel("Reload page")
          .keyboardShortcut("r", modifiers: .command)
        VStack(alignment: .leading, spacing: 2) {
          Text(page.pageTitle).font(.callout.weight(.medium)).lineLimit(1)
          Text(page.currentURL?.absoluteString ?? page.originalURL.absoluteString)
            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if page.isLoading { ProgressView().controlSize(.small).accessibilityLabel("Loading page") }
        Button("Open in Default Browser", action: page.openInDefaultBrowser)
      }
      .buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 10)
      if let message = page.message {
        Text(message).font(.callout).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading).padding(12)
      }
      Divider()
      PersistentBrowserView(webView: page.webView)
      Divider()
      Text(page.footer)
        .font(.caption).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 6)
    }
    .frame(minWidth: 640, minHeight: 420)
  }
}

private struct PersistentBrowserView: NSViewRepresentable {
  let webView: WKWebView
  func makeNSView(context: Context) -> WKWebView { webView }
  func updateNSView(_ view: WKWebView, context: Context) {}
}
