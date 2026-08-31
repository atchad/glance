import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, ObservableObject, NSWindowDelegate {
  private let store: AppStore
  private let panelController: FloatingPanelController
  private var window: NSWindow?

  init(store: AppStore, panelController: FloatingPanelController) {
    self.store = store
    self.panelController = panelController
  }

  func show() {
    let window = window ?? makeWindow()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 465),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Glance Settings"
    window.minSize = NSSize(width: 500, height: 420)
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
}
