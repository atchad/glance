import AppKit
import SwiftUI

@main
struct GlanceApp: App {
  @StateObject private var store: AppStore
  @StateObject private var panel: FloatingPanelController
  @StateObject private var settingsWindow: SettingsWindowController
  @StateObject private var statusItem: StatusItemController

  init() {
    UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 2.0])
    let store = AppStore()
    let panel = FloatingPanelController(store: store)
    let settingsWindow = SettingsWindowController(store: store, panelController: panel)
    panel.setOpenSettingsAction(settingsWindow.show)
    let statusItem = StatusItemController(
      store: store, panel: panel, settingsWindow: settingsWindow)
    _store = StateObject(wrappedValue: store)
    _panel = StateObject(wrappedValue: panel)
    _settingsWindow = StateObject(wrappedValue: settingsWindow)
    _statusItem = StateObject(wrappedValue: statusItem)
    DispatchQueue.main.async {
      NSApp.setActivationPolicy(.accessory)
      store.start()
      if store.preferences.openPanelAtLaunch { panel.show() }
    }
  }

  var body: some Scene {
    Settings {
      GlanceSettingsView(store: store, panel: panel)
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { settingsWindow.show() }
          .keyboardShortcut(",")
      }
      CommandGroup(replacing: .appTermination) {
        Button("Quit Glance") { NSApplication.shared.terminate(nil) }
          .keyboardShortcut("q")
      }
    }
  }
}
