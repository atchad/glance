import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, ObservableObject, NSWindowDelegate {
  private static let swiftUISidebarToggleIdentifier = NSToolbarItem.Identifier(
    "com.apple.SwiftUI.navigationSplitView.toggleSidebar")

  private let store: AppStore
  private let panelController: FloatingPanelController
  private var window: NSWindow?
  private weak var observedToolbar: NSToolbar?

  init(store: AppStore, panelController: FloatingPanelController) {
    self.store = store
    self.panelController = panelController
  }

  func show() {
    let window = window ?? makeWindow()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    removeSidebarToggle(from: window)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "Glance Settings"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.minSize = NSSize(width: 720, height: 540)
    window.contentMinSize = NSSize(width: 720, height: 540)
    window.setFrameAutosaveName("GlanceSettingsWindow")
    window.isReleasedWhenClosed = false
    window.contentViewController = NSHostingController(
      rootView: GlanceSettingsView(store: store, panel: panelController)
    )
    window.center()
    window.delegate = self
    self.window = window
    return window
  }

  private func removeSidebarToggle(from window: NSWindow, attemptsRemaining: Int = 10) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak window] in
      guard let self, let window else { return }
      if let toolbar = window.toolbar {
        self.observeToolbarIfNeeded(toolbar)
        toolbar.isVisible = true
      }
      if let toolbar = window.toolbar,
        let index = toolbar.items.firstIndex(where: {
          $0.itemIdentifier == .toggleSidebar
            || $0.itemIdentifier == Self.swiftUISidebarToggleIdentifier
        })
      {
        toolbar.removeItem(at: index)
      } else if attemptsRemaining > 0 {
        self.removeSidebarToggle(from: window, attemptsRemaining: attemptsRemaining - 1)
      }
    }
  }

  private func observeToolbarIfNeeded(_ toolbar: NSToolbar) {
    guard observedToolbar !== toolbar else { return }
    if let observedToolbar {
      NotificationCenter.default.removeObserver(
        self, name: NSToolbar.willAddItemNotification, object: observedToolbar)
    }
    observedToolbar = toolbar
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(toolbarWillAddItem),
      name: NSToolbar.willAddItemNotification,
      object: toolbar)
  }

  @objc private func toolbarWillAddItem(_ notification: Notification) {
    guard let window else { return }
    removeSidebarToggle(from: window)
  }
}
