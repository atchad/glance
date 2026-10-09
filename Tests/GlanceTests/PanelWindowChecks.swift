import AppKit
@testable import Glance

/// Exercise real AppKit controls, the window controller, and SwiftUI hosting, not just size math.
@MainActor
enum PanelWindowChecks {
  private struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  static func run() throws -> Int {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    if !NSApp.isRunning { NSApp.finishLaunching() }
    NSApp.activate(ignoringOtherApps: true)
    pump()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Glance-panel-tests-\(UUID().uuidString)")
    let suite = "Glance-panel-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    defer {
      NSStatusBar.system.removeStatusItem(item)
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("fixture", sections.map { SectionSnapshot(id: $0.id, pullRequests: []) })
    })
    let keys = KeybindingStore(url: directory.appendingPathComponent("keybindings.json"), watch: false)
    let updates = UpdateController(startingUpdater: false)
    let commands = ApplicationCommands(store: store, updates: updates)
    let panel = FloatingPanelController(store: store, keys: keys, commands: commands, defaults: defaults)
    let settings = SettingsWindowController(store: store, panelController: panel,
      updateController: updates, keys: keys, commands: commands)
    commands.configure(panel: panel, settings: settings)
    let menuPopover = NSPopover()
    menuPopover.animates = false
    let status = StatusItemController(store: store, keys: keys, commands: commands, panel: panel,
      statusItem: item, popover: menuPopover)
    defer { panel.hide() }
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
      checks += 1
      guard condition() else { throw Failure(message: message) }
    }

    pump() // Let AppKit attach and position the status item before anchoring a popover.
    try withExtendedLifetime(status) {
      for value in ["840", "0", "-1", "\"NaN\"", "null"] {
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(
          "{\"menuBarWindowHeight\":\(value),\"showAuthor\":false}".utf8))
        try check(!preferences.showAuthor && !preferences.recoveredInvalidValues,
          "The removed height setting must not invalidate existing preferences.")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as! [String: Any]
        try check(encoded["menuBarWindowHeight"] == nil, "Do not persist the obsolete height setting.")
      }
      item.button!.performClick(nil)
      pump()
      try check(status.isPopoverShown && !panel.isVisible,
        "The menu-bar button must open a popover without opening the floating panel.")
      try check(menuPopover.contentSize == NSSize(width: 390, height: 590),
        "The menu-bar surface must retain its compact content size after hosting attaches.")
      item.button!.performClick(nil)
      pump()
      try check(!status.isPopoverShown && !panel.isVisible,
        "Clicking the menu-bar button again must close the popover.")
      item.button!.performClick(nil)
      pump()
      try check(status.isPopoverShown, "The menu-bar popover must reopen.")
      commands.perform(.showPanel)
      pump()
      try check(panel.isVisible && !status.isPopoverShown,
        "Showing the floating panel must dismiss the menu-bar popover.")
      guard let window = NSApp.windows.first(where: { $0.title == "Glance" && $0.isVisible }) else {
        throw Failure(message: "The Show floating panel command did not create the Glance window.")
      }
      try check(window is NSPanel && window.styleMask.contains(.resizable), "The displayed window must have native resize edges.")
      let originalFrame = window.frame
      let visibleFrame = (window.screen ?? NSScreen.main)!.visibleFrame
      for height in resizeHeights(for: window, visibleFrame: visibleFrame) {
        window.setContentSize(NSSize(width: 410, height: height))
        window.contentView?.layoutSubtreeIfNeeded()
        pump()
        try check(abs(window.contentRect(forFrameRect: window.frame).height - height) < 1,
          "SwiftUI hosting must retain the resized content height \(height); actual \(window.contentRect(forFrameRect: window.frame).height), visible frame \(visibleFrame).")
        let stored = defaults.string(forKey: "floatingPanelFrame").map(NSRectFromString)
        try check(stored == window.frame, "Native resize notifications must save the complete window frame.")
      }
      let resizedFrame = window.frame
      try check(resizedFrame != originalFrame, "The panel must accept a new height.")
      item.button!.performClick(nil)
      pump()
      try check(status.isPopoverShown && !panel.isVisible,
        "A menu-bar click with the panel open must switch to the popover.")
      item.button!.performClick(nil)
      pump()
      try check(!status.isPopoverShown, "The menu-bar button must close the popover.")
      panel.toggleFromHotkey()
      pump()
      try check(window.isVisible && window.frame == resizedFrame,
        "The hotkey must reuse the floating panel's saved frame.")

      let popover = NSPopover()
      popover.animates = false
      popover.behavior = .transient
      let content = NSViewController()
      content.view = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 120))
      content.view.addSubview(NSTextField(frame: NSRect(x: 10, y: 10, width: 160, height: 24)))
      popover.contentViewController = content
      popover.show(relativeTo: NSRect(x: 20, y: 20, width: 24, height: 24),
        of: window.contentView!, preferredEdge: .maxX)
      content.view.window?.makeKey()
      pump()
      try check(popover.isShown && content.view.window?.isKeyWindow == true && panel.isVisible,
        "Focusing a details popover must not hide its dashboard.")
      popover.close()
      window.makeKeyAndOrderFront(nil)
      pump()
      try check(panel.isVisible, "Closing details must keep the dashboard open.")

      let sheet = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 180, height: 120),
        styleMask: [.titled], backing: .buffered, defer: false)
      sheet.isReleasedWhenClosed = false
      window.beginSheet(sheet)
      pump()
      try check(sheet.isKeyWindow && panel.isVisible, "Focusing a dashboard sheet must keep the dashboard visible.")
      window.endSheet(sheet)
      sheet.orderOut(nil)
      window.makeKeyAndOrderFront(nil)
      pump()

      let child = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 180, height: 120),
        styleMask: [.titled], backing: .buffered, defer: false)
      child.isReleasedWhenClosed = false
      window.addChildWindow(child, ordered: .above)
      child.makeKeyAndOrderFront(nil)
      pump()
      try check(child.isKeyWindow && panel.isVisible, "Focusing a child window must keep the dashboard visible.")
      child.orderOut(nil)
      window.removeChildWindow(child)
      window.makeKeyAndOrderFront(nil)
      pump()

      let outside = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 180, height: 120),
        styleMask: [.titled], backing: .buffered, defer: false)
      outside.isReleasedWhenClosed = false
      defer { outside.orderOut(nil) }
      outside.makeKeyAndOrderFront(nil)
      pump()
      try check(outside.isKeyWindow && !panel.isVisible, "Focusing an unrelated window must hide the dashboard.")
      outside.orderOut(nil)
      panel.show()
      pump()
      try check(panel.isVisible && window.frame == resizedFrame, "Outside dismissal must preserve the panel's frame for reopening.")
      NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
      pump()
      try check(!panel.isVisible, "Switching to another application must hide the dashboard.")
      NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
      pump()
      try check(!panel.isVisible, "Reactivating Glance must not reopen a dismissed dashboard.")
      let appDelegate = GlanceAppDelegate()
      appDelegate.commands = commands
      try check(!appDelegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true) && !panel.isVisible,
        "Clicking the Dock icon must only bring forward Glance windows that are already visible.")
      try check(!appDelegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false),
        "Glance must handle a Dock click when none of its windows are visible.")
      pump()
      try check(panel.isVisible && window.frame == resizedFrame,
        "Clicking the Dock icon with no visible windows must reopen the dashboard in its saved frame.")
      panel.hide()

      let restored = FloatingPanelController(store: store, keys: keys, commands: commands, defaults: defaults)
      restored.show()
      pump()
      defer { restored.hide() }
      let restoredWindow = NSApp.windows.first { $0.title == "Glance" && $0.isVisible }
      try check(restoredWindow?.frame == resizedFrame, "A new controller must restore the resized frame from disk.")

      restored.hide()
      panel.show()
      pump()
      commands.showRepositoryColors(for: "Owner/Repo")
      pump()
      guard let settingsWindow = NSApp.windows.first(where: { $0.title == SettingsCategory.repoColors.title && $0.isVisible }) else {
        throw Failure(message: "The repository color action must open Settings.")
      }
      defer { settingsWindow.orderOut(nil) }
      try check(!panel.isVisible, "Opening repository colors must hide the originating dashboard.")
      try check(settings.navigation.category == .repoColors && settings.navigation.repository == "owner/repo",
        "The color action must select Repo Colors and the requested repository.")
      try check(store.preferences.repositoryColor(for: "owner/repo") != nil,
        "A repository deep link must have an assigned color before the editor appears.")
      commands.showRepositoryColors(for: "Other/Repo")
      pump()
      try check(settings.navigation.repository == "other/repo" && settingsWindow.isVisible,
        "A second repository link must update the existing Settings window.")
      settings.navigation.category = .keyboard
      commands.showRepositoryColors(for: "Other/Repo")
      pump()
      try check(settings.navigation.category == .repoColors,
        "A repeated repository link must restore its color settings after visiting Keyboard.")
    }
    return checks
  }

  static func resizeHeights(for window: NSWindow, visibleFrame: NSRect) -> [CGFloat] {
    // AppKit clamps oversized windows to the screen. Scale the test's resize
    // range above its minimum so small CI displays still exercise distinct sizes.
    let minimum = window.contentMinSize.height
    let maximum = floor(window.contentRect(forFrameRect: visibleFrame).height)
    let scale = min(1, (maximum - minimum) / (700 - minimum))
    return [420, 700, 500].map { floor(minimum + ($0 - minimum) * scale) }
  }

  private static func pump() {
    // Focus transitions arrive as AppKit events, not just run-loop callbacks.
    let deadline = Date().addingTimeInterval(0.4)
    while Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
      if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01),
        inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
    }
  }
}
