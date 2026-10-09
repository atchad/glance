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
  @StateObject private var keys: KeybindingStore
  @StateObject private var commands: ApplicationCommands

  init() {
    UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 2.0])
    let store = AppStore()
    let updates = UpdateController()
    let keys = KeybindingStore(legacyShortcut: store.preferences.globalShortcut)
    let commands = ApplicationCommands(store: store, updates: updates)
    let panel = FloatingPanelController(store: store, keys: keys, commands: commands)
    let settingsWindow = SettingsWindowController(
      store: store, panelController: panel, updateController: updates, keys: keys, commands: commands)
    commands.configure(panel: panel, settings: settingsWindow)
    let statusItem = StatusItemController(
      store: store, keys: keys, commands: commands, panel: panel)
    let globalShortcut = GlobalShortcutController(keys: keys) {
      panel.toggleFromHotkey()
    }
    _store = StateObject(wrappedValue: store)
    _panel = StateObject(wrappedValue: panel)
    _settingsWindow = StateObject(wrappedValue: settingsWindow)
    _statusItem = StateObject(wrappedValue: statusItem)
    _updates = StateObject(wrappedValue: updates)
    _globalShortcut = StateObject(wrappedValue: globalShortcut)
    _keys = StateObject(wrappedValue: keys)
    _commands = StateObject(wrappedValue: commands)
    DispatchQueue.main.async {
      NSApp.setActivationPolicy(.accessory)
      store.enablePullRequestBrowser()
      store.configureLoginItemAtLaunch()
      store.start()
      if store.preferences.openPanelAtLaunch { panel.show() }
    }
  }

  var body: some Scene {
    Settings {
      GlanceSettingsView(store: store, panel: panel, updates: updates, keys: keys, commands: commands,
        navigation: settingsWindow.navigation)
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        CommandButton(keys: keys, action: .settings, perform: { commands.perform(.settings) })
      }
      CommandGroup(after: .appInfo) {
        CommandButton(keys: keys, action: .checkForUpdates,
          perform: { commands.perform(.checkForUpdates) }, enabled: updates.canCheckForUpdates)
      }
      CommandGroup(replacing: .appTermination) {
        CommandButton(keys: keys, action: .quit, perform: { commands.perform(.quit) })
      }
    }
  }
}
