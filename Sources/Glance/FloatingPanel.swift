import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, ObservableObject, NSWindowDelegate {
  private let store: AppStore
  private let keys: KeybindingStore
  private let commands: ApplicationCommands
  private let defaults: UserDefaults
  private var panel: NSPanel?
  private var titleBarMonitor: Any?
  private var focusObservers: [NSObjectProtocol] = []
  private var frameBeforeFill: NSRect?

  deinit {
    if let titleBarMonitor { NSEvent.removeMonitor(titleBarMonitor) }
    focusObservers.forEach(NotificationCenter.default.removeObserver)
  }
  init(store: AppStore, keys: KeybindingStore, commands: ApplicationCommands, defaults: UserDefaults = .standard) {
    self.store = store
    self.keys = keys
    self.commands = commands
    self.defaults = defaults
    super.init()
    let center = NotificationCenter.default
    focusObservers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
      object: NSApp, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.hide() }
      })
    focusObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification,
      object: nil, queue: .main) { [weak self] notification in
        MainActor.assumeIsolated {
          guard let window = notification.object as? NSWindow else { return }
          self?.hideIfFocusOutside(window)
        }
      })
  }

  var isVisible: Bool { panel?.isVisible == true && panel?.isMiniaturized == false }

  func toggleFromHotkey() {
    Self.shouldHideFromHotkey(isVisible: isVisible, isKey: panel?.isKeyWindow == true) ? hide() : show()
  }

  nonisolated static func shouldHideFromHotkey(isVisible: Bool, isKey: Bool) -> Bool { isVisible && isKey }

  func show() {
    let panel = panel ?? makePanel()
    applyLevel()
    if panel.isMiniaturized { panel.deminiaturize(nil) }
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    objectWillChange.send()
  }

  func hide() {
    panel?.orderOut(nil)
    objectWillChange.send()
  }

  private func hideIfFocusOutside(_ window: NSWindow) {
    guard isVisible else { return }
    // Details popovers and sheets belong to the dashboard, not an outside click.
    var ancestor: NSWindow? = window
    while let current = ancestor {
      if current === panel { return }
      ancestor = current.sheetParent ?? current.parent
    }
    hide()
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
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.title = "Glance"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isFloatingPanel = true
    // Explicitly order out on deactivation so reactivating the app cannot reopen it.
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isMovableByWindowBackground = true
    panel.minSize = NSSize(width: 310, height: 320)
    panel.contentMinSize = NSSize(width: 310, height: 320)
    panel.showsResizeIndicator = true
    panel.standardWindowButton(.zoomButton)?.isEnabled = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentViewController = NSHostingController(
      rootView: DashboardView(store: store, keys: keys, commands: commands,
        close: { [weak self] in self?.hide() })
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
    guard frameBeforeFill == nil else { return }
    defaults.set(NSStringFromRect(panel.frame), forKey: "floatingPanelFrame")
  }

  private func installTitleBarMonitor(for panel: NSPanel) {
    titleBarMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
      [weak self, weak panel] event in
      guard let self, let panel, event.window === panel, event.clickCount == 2,
        event.locationInWindow.y >= panel.contentLayoutRect.maxY else { return event }
      let preference = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
      if preference == nil || preference == "Maximize" || preference == "Zoom" {
        self.frameBeforeFill = nil
      }
      Self.performTitleBarAction(
        for: panel, preference: preference, fill: { self.toggleFill(panel) })
      return nil
    }
  }

  static func performTitleBarAction(for panel: NSPanel, preference: String?, fill: () -> Void) {
    switch preference ?? "Maximize" {
    case "Minimize": panel.miniaturize(nil)
    case "Fill": fill()
    // macOS stores the system settings “Zoom” choice as “Maximize”.
    case "Maximize", "Zoom": panel.performZoom(nil)
    default: break
    }
  }

  private func toggleFill(_ panel: NSPanel) {
    if let restoreFrame = frameBeforeFill {
      panel.setFrame(restoreFrame, display: true, animate: true)
      frameBeforeFill = nil
      saveFrame()
      return
    }
    guard let screen = panel.screen ?? NSScreen.main else { return }
    frameBeforeFill = panel.frame
    panel.setFrame(screen.visibleFrame, display: true, animate: true)
  }

  private func restoredFrame() -> NSRect? {
    guard let value = defaults.string(forKey: "floatingPanelFrame") else { return nil }
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
