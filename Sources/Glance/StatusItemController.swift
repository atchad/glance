import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, ObservableObject {
  private let store: AppStore
  private let keys: KeybindingStore
  private let commands: ApplicationCommands
  private let panel: FloatingPanelController
  private let statusItem: NSStatusItem
  private var cancellables: Set<AnyCancellable> = []

  init(
    store: AppStore, keys: KeybindingStore, commands: ApplicationCommands,
    panel: FloatingPanelController,
    statusItem: NSStatusItem? = nil
  ) {
    self.store = store
    self.keys = keys
    self.commands = commands
    self.panel = panel
    self.statusItem = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    if let button = self.statusItem.button {
      button.image = Octicon.pullRequest.image
      button.imagePosition = .imageLeading
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseDown])
    }

    store.$snapshots
      .combineLatest(store.$preferences)
      .receive(on: RunLoop.main)
      .sink { [weak self] _, _ in self?.updateButton() }
      .store(in: &cancellables)
    store.$isRefreshing.combineLatest(store.$lastUpdated, store.$connectionIssue)
      .receive(on: RunLoop.main)
      .sink { [weak self] _, _, _ in self?.updateButton() }
      .store(in: &cancellables)
    updateButton()
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseDown {
      showContextMenu(from: sender)
    } else {
      commands.perform(panel.isVisible ? .hidePanel : .showPanel)
    }
  }

  private func showContextMenu(from button: NSStatusBarButton) {
    let menu = NSMenu()
    addMenuItem(.settings, selector: #selector(openSettings), to: menu)
    addMenuItem(.checkForUpdates, selector: #selector(checkForUpdates), to: menu)
    menu.addItem(.separator())
    addMenuItem(.quit, selector: #selector(quit), to: menu)
    menu.autoenablesItems = false
    menu.popUp(positioning: menu.items.first, at: NSPoint(x: 0, y: -4), in: button)
  }

  private func addMenuItem(_ action: GlanceAction, selector: Selector, to menu: NSMenu) {
    let chord = keys.menuChord(for: action)
    let item = menu.addItem(withTitle: action.title, action: selector, keyEquivalent: chord?.keyEquivalent ?? "")
    item.keyEquivalentModifierMask = chord?.eventModifiers ?? []
    item.target = self
    item.isEnabled = commands.canPerform(action)
  }

  private func updateButton() {
    guard let button = statusItem.button else { return }
    button.image = Octicon.pullRequest.image
    button.setAccessibilityLabel("Glance pull requests")
    button.setAccessibilityHelp("Show or hide the resizable pull request panel")
    button.setAccessibilityValue(Self.accessibilityValue(
      count: store.menuBarCount, mode: store.preferences.menuBarCountMode,
      isRefreshing: store.isRefreshing, lastUpdated: store.lastUpdated,
      connectionIssue: store.connectionIssue))
    if let count = store.menuBarCount {
      button.title = " \(count)"
    } else {
      button.title = ""
    }
  }

  static func accessibilityValue(
    count: Int?, mode: MenuBarCountMode, isRefreshing: Bool, lastUpdated: Date?,
    connectionIssue: AppConnectionIssue?
  ) -> String {
    let countDescription = count.map { "\($0) — \(mode.title)" } ?? "Count hidden"
    let freshness: String
    if isRefreshing {
      freshness = "Refreshing"
    } else if connectionIssue != nil {
      freshness = lastUpdated == nil
        ? "Refresh unavailable; no results loaded"
        : "Refresh unavailable; showing saved results"
    } else if let date = lastUpdated {
      freshness = "Last updated \(date.formatted(date: .abbreviated, time: .shortened))"
    } else {
      freshness = "Not refreshed yet"
    }
    return "\(countDescription). \(freshness)"
  }

  @objc private func openSettings() {
    commands.perform(.settings)
  }

  @objc private func checkForUpdates() {
    commands.perform(.checkForUpdates)
  }

  @objc private func quit() { commands.perform(.quit) }
}
