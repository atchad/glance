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
    let savedFrame = restoredFrame()
    let initialContentRect = NSRect(x: 80, y: 160, width: 410, height: 620)
    let panel = NSPanel(
      contentRect: initialContentRect,
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
    panel.contentViewController = NSHostingController(
      rootView: DashboardView(store: store, surface: .panel, openSettings: openSettingsAction)
    )
    // Hosting attachment can resize the window to the view's minimum. Apply geometry
    // afterwards, keeping persisted outer frames distinct from the default content size.
    if let savedFrame {
      panel.setFrame(savedFrame, display: false)
    } else {
      panel.setContentSize(initialContentRect.size)
      panel.setFrameOrigin(initialContentRect.origin)
    }
    if let screen = panel.screen ?? NSScreen.main {
      panel.setFrame(Self.constrainedFrame(panel.frame, to: screen.visibleFrame), display: false)
    }
    self.panel = panel
    // Only persist finished geometry, never intermediate hosting/construction sizes.
    panel.delegate = self
    saveFrame()
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

  nonisolated static func constrainedFrame(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
    let size = NSSize(
      width: min(frame.width, visibleFrame.width),
      height: min(frame.height, visibleFrame.height)
    )
    return NSRect(
      x: max(visibleFrame.minX, min(frame.minX, visibleFrame.maxX - size.width)),
      y: max(visibleFrame.minY, min(frame.minY, visibleFrame.maxY - size.height)),
      width: size.width,
      height: size.height
    )
  }
}
