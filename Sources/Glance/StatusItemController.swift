import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, ObservableObject {
  private let store: AppStore
  private let panel: FloatingPanelController
  private let settingsWindow: SettingsWindowController
  private let updateController: UpdateController
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private var cancellables: Set<AnyCancellable> = []

  init(
    store: AppStore, panel: FloatingPanelController, settingsWindow: SettingsWindowController,
    updateController: UpdateController
  ) {
    self.store = store
    self.panel = panel
    self.settingsWindow = settingsWindow
    self.updateController = updateController
    super.init()

    popover.behavior = .transient
    popover.animates = true
    popover.contentSize = NSSize(width: 390, height: 590)
    popover.contentViewController = NSHostingController(
      rootView: DashboardView(
        store: store, surface: .menuBar, togglePanel: panel.toggle,
        openSettings: { [weak self] in self?.showSettingsFromPopover() },
        didOpenPullRequest: { [weak self] in self?.popover.performClose(nil) })
    )

    if let button = statusItem.button {
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
    updateButton()
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }
    if event.type == .rightMouseDown {
      showContextMenu(from: sender)
    } else {
      togglePopover(from: sender)
    }
  }

  private func togglePopover(from button: NSStatusBarButton) {
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  private func showContextMenu(from button: NSStatusBarButton) {
    popover.performClose(nil)
    let menu = NSMenu()
    menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
      .target = self
    let updateItem = menu.addItem(
      withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    updateItem.target = self
    updateItem.isEnabled = updateController.canCheckForUpdates
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit Glance", action: #selector(quit), keyEquivalent: "q").target =
      self
    menu.autoenablesItems = false
    menu.popUp(positioning: menu.items.first, at: NSPoint(x: 0, y: -4), in: button)
  }

  private func updateButton() {
    guard let button = statusItem.button else { return }
    button.image = Octicon.pullRequest.image
    if let count = store.menuBarCount {
      button.title = " \(count)"
    } else {
      button.title = ""
    }
  }

  @objc private func openSettings() {
    showSettingsFromPopover()
  }

  @objc private func checkForUpdates() {
    updateController.checkForUpdates()
  }

  private func showSettingsFromPopover() {
    popover.performClose(nil)
    panel.hide()
    settingsWindow.show()
  }

  @objc private func quit() { NSApp.terminate(nil) }
}
