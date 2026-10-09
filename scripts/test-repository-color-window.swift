import AppKit
@testable import Glance

/// Deep links use the actual Settings controller, with isolated preferences and no GitHub calls.
@main
struct RepositoryColorWindowTestRunner {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let previousApp = NSWorkspace.shared.frontmostApplication
    let directory = URL(fileURLWithPath: CommandLine.arguments[1])
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("fixture", sections.map { SectionSnapshot(id: $0.id, pullRequests: []) })
    })
    let keys = KeybindingStore(url: directory.appendingPathComponent("keybindings.json"), watch: false)
    let updates = UpdateController(startingUpdater: false)
    let commands = ApplicationCommands(store: store, updates: updates)
    let panel = FloatingPanelController(store: store, keys: keys, commands: commands)
    let settings = SettingsWindowController(store: store, panelController: panel,
      updateController: updates, keys: keys, commands: commands)
    commands.configure(panel: panel, settings: settings)
    defer {
      app.windows.forEach { $0.orderOut(nil) }
      previousApp?.activate(options: [])
    }
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
      guard condition() else {
        fputs("FAILED: \(message)\n", stderr)
        exit(EXIT_FAILURE)
      }
      checks += 1
    }
    for repository in ["Owner/Repo", "Other/Repo", "Other/Repo"] {
      settings.navigation.category = .general
      commands.showRepositoryColors(for: repository)
      let deadline = Date().addingTimeInterval(0.2)
      while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
      }
      check(app.windows.contains { $0.title == SettingsCategory.repoColors.title && $0.isVisible },
        "The repository color action must open Settings.")
      check(settings.navigation.category == .repoColors,
        "Each link must restore the Repo Colors category.")
      check(settings.navigation.repository == repository.lowercased(),
        "Each link must select the requested repository.")
      check(store.preferences.repositoryColor(for: repository) != nil,
        "Assign a color before showing its editor.")
    }
    print("Passed \(checks) repository color window checks.")
  }
}
