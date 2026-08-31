import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, ObservableObject, NSWindowDelegate {
  private let store: AppStore
  private var panel: NSPanel?
  private var openSettingsAction: () -> Void = {}
  private var titleBarMonitor: Any?
  private var frameBeforeZoom: NSRect?

  deinit {
    if let titleBarMonitor { NSEvent.removeMonitor(titleBarMonitor) }
  }

  init(store: AppStore) { self.store = store }

  func setOpenSettingsAction(_ action: @escaping () -> Void) {
    openSettingsAction = action
  }

  var isVisible: Bool { panel?.isVisible == true }

  func toggle() { isVisible ? hide() : show() }

  func show() {
    let panel = panel ?? makePanel()
    applyLevel()
    panel.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    objectWillChange.send()
  }

  func hide() {
    panel?.orderOut(nil)
    objectWillChange.send()
  }

  func applyLevel() {
    panel?.level = store.preferences.panelLevel == .floating ? .floating : .normal
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    objectWillChange.send()
    return false
  }

  private func makePanel() -> NSPanel {
    let frame = restoredFrame() ?? NSRect(x: 80, y: 160, width: 410, height: 620)
    let panel = NSPanel(
      contentRect: frame,
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.title = "Glance"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isMovableByWindowBackground = true
    panel.minSize = NSSize(width: 310, height: 320)
    panel.contentMinSize = NSSize(width: 310, height: 320)
    panel.showsResizeIndicator = true
    panel.standardWindowButton(.zoomButton)?.isEnabled = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.delegate = self
    panel.contentViewController = NSHostingController(
      rootView: DashboardView(store: store, surface: .panel, openSettings: openSettingsAction)
    )
    self.panel = panel
    installTitleBarMonitor(for: panel)
    return panel
  }

  func windowDidMove(_ notification: Notification) { saveFrame() }
  func windowDidResize(_ notification: Notification) { saveFrame() }

  private func saveFrame() {
    guard let panel else { return }
    guard frameBeforeZoom == nil else { return }
    UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "floatingPanelFrame")
  }

  private func installTitleBarMonitor(for panel: NSPanel) {
    titleBarMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
      [weak self, weak panel] event in
      guard let self, let panel, event.window === panel, event.clickCount == 2 else { return event }
      let titleBarBottom = panel.contentLayoutRect.maxY
      guard event.locationInWindow.y >= titleBarBottom else { return event }
      self.toggleZoom(panel)
      return nil
    }
  }

  private func toggleZoom(_ panel: NSPanel) {
    if let restoreFrame = frameBeforeZoom {
      panel.setFrame(restoreFrame, display: true, animate: true)
      frameBeforeZoom = nil
      saveFrame()
      return
    }
    guard let screen = panel.screen ?? NSScreen.main else { return }
    frameBeforeZoom = panel.frame
    panel.setFrame(screen.visibleFrame, display: true, animate: true)
  }

  private func restoredFrame() -> NSRect? {
    guard let value = UserDefaults.standard.string(forKey: "floatingPanelFrame") else { return nil }
    let frame = NSRectFromString(value)
    guard frame.width >= 310, frame.height >= 320 else { return nil }
    return NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) ? frame : nil
  }
}
