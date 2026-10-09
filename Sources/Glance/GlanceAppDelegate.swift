import AppKit
import Combine

/// Reopen the dashboard from the Dock when no Glance window is visible.
@MainActor
final class GlanceAppDelegate: NSObject, NSApplicationDelegate {
  var commands: ApplicationCommands?
  private var dockIconSubscription: AnyCancellable?

  func configureDockIcon(
    store: AppStore,
    applyPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) }
  ) {
    dockIconSubscription = store.$preferences
      .map(\.showDockIcon)
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { visible in
        MainActor.assumeIsolated { applyPolicy(visible ? .regular : .accessory) }
      }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    guard !hasVisibleWindows, let commands else { return true }
    return !commands.perform(.showPanel)
  }
}
