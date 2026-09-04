import AppKit
import SwiftUI

@main
struct GlanceApp: App {
  @StateObject private var store: AppStore
  @StateObject private var panel: FloatingPanelController
  @StateObject private var settingsWindow: SettingsWindowController
  @StateObject private var statusItem: StatusItemController
  @StateObject private var updates: UpdateController
  @StateObject private var globalShortcut: GlobalShortcutController

  init() {
    UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 2.0])
    let store = AppStore()
    let panel = FloatingPanelController(store: store)
    let updates = UpdateController()
    let settingsWindow = SettingsWindowController(
      store: store, panelController: panel, updateController: updates)
    panel.setOpenSettingsAction(settingsWindow.show)
    let statusItem = StatusItemController(
      store: store, panel: panel, settingsWindow: settingsWindow, updateController: updates)
    let globalShortcut = GlobalShortcutController(store: store, action: panel.toggle)
    _store = StateObject(wrappedValue: store)
    _panel = StateObject(wrappedValue: panel)
    _settingsWindow = StateObject(wrappedValue: settingsWindow)
    _statusItem = StateObject(wrappedValue: statusItem)
    _updates = StateObject(wrappedValue: updates)
    _globalShortcut = StateObject(wrappedValue: globalShortcut)
    DispatchQueue.main.async {
      NSApp.setActivationPolicy(.accessory)
      store.configureLoginItemAtLaunch()
      store.start()
      if store.preferences.openPanelAtLaunch { panel.show() }
    }
  }

  var body: some Scene {
    Settings {
      GlanceSettingsView(store: store, panel: panel, updates: updates)
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { settingsWindow.show() }
          .keyboardShortcut(",")
      }
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…") { updates.checkForUpdates() }
          .disabled(!updates.canCheckForUpdates)
      }
      CommandGroup(replacing: .appTermination) {
        Button("Quit Glance") { NSApplication.shared.terminate(nil) }
          .keyboardShortcut("q")
      }
    }
  }
}
