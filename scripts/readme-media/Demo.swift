import AppKit
import SwiftUI
@testable import Glance

/// Offline marketing fixture. Never starts the live client, updater, login item or browser.
@main
struct ReadmeDemo {
  @MainActor static func main() throws {
    guard CommandLine.arguments.count == 2,
      ProcessInfo.processInfo.environment["HOME"] == CommandLine.arguments[1],
      ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] == CommandLine.arguments[1]
    else { fatalError("An isolated HOME and CFFIXED_USER_HOME are required") }
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.finishLaunching()
    let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("fixture")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var preferences = Preferences.default
    preferences.openAtLogin = false
    preferences.notificationsEnabled = false
    preferences.appearanceMode = .dark
    preferences.showDockIcon = false
    try JSONEncoder().encode(preferences).write(to: directory.appendingPathComponent("preferences.json"))
    let rows = [
      fixture(128, "northstar/desktop", "Keep search results in sync across windows", "alex", .success, .clean),
      fixture(94, "northstar/api", "Retry interrupted uploads without losing progress", "sam", .failure, .blocked),
      fixture(52, "northstar/design", "Add a compact layout for the activity feed", "jules", .pending, .unknown),
      fixture(126, "northstar/desktop", "Restore keyboard focus after closing a sheet", "morgan", .success, .conflicting),
      fixture(89, "northstar/api", "Cache repository permissions between refreshes", "demo", .success, .clean),
      fixture(49, "northstar/design", "Polish the empty state for saved searches", "demo", .pending, .unknown, draft: true),
    ]
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("demo", sections.enumerated().map { index, section in
        SectionSnapshot(id: section.id, pullRequests: index == 0 ? Array(rows.prefix(4)) : Array(rows.suffix(2)))
      })
    }, performMergeAction: { _, _ in throw NSError(domain: "OfflineDemo", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Offline demonstration: GitHub actions are disabled."]) })
    let keys = KeybindingStore(url: directory.appendingPathComponent("keybindings.json"), watch: false)
    let updates = UpdateController(startingUpdater: false)
    let commands = ApplicationCommands(store: store, updates: updates)
    let panel = FloatingPanelController(store: store, keys: keys, commands: commands,
      defaults: UserDefaults.standard)
    let settings = SettingsWindowController(store: store, panelController: panel,
      updateController: updates, keys: keys, commands: commands)
    commands.configure(panel: panel, settings: settings)
    // A solid app-owned backdrop prevents translucent windows from showing the desktop.
    let backdrop = NSWindow(contentRect: NSScreen.main!.frame, styleMask: .borderless,
      backing: .buffered, defer: false)
    backdrop.backgroundColor = NSColor(srgbRed: 0.075, green: 0.09, blue: 0.13, alpha: 1)
    backdrop.level = .normal
    backdrop.orderFront(nil)
    store.refresh()
    panel.show()
    if let window = app.windows.first(where: { $0.title == "Glance" }) {
      window.setContentSize(NSSize(width: 440, height: 610))
      window.center()
    }
    withExtendedLifetime((store, keys, updates, commands, panel, settings, backdrop)) { app.run() }
  }

  static func fixture(_ number: Int, _ repo: String, _ title: String, _ author: String,
    _ checks: PullRequest.CheckState, _ merge: PullRequest.MergeState, draft: Bool = false) -> PullRequest {
    let age = TimeInterval([128: 1800, 94: 7200, 52: 10800, 126: 86400, 89: 14400, 49: 172800][number]!)
    let created = Date().addingTimeInterval(-age)
    return PullRequest(id: "DEMO_\(number)", number: number, repository: repo, title: title,
      author: author, authorAvatarURL: nil, url: URL(string: "https://example.invalid/\(repo)/pull/\(number)")!,
      branch: "demo/pr-\(number)", headRefOID: "demo-revision-\(number)", createdAt: created,
      reviewRequestedAt: author == "demo" ? nil : created, updatedAt: created, isDraft: draft,
      reviewDecision: author == "demo" && !draft ? "APPROVED" : "REVIEW_REQUIRED", checksState: checks,
      additions: number + 12, deletions: number / 4, labels: [], requestedReviewers: ["demo"],
      viewerReviewState: nil, viewerReviewedHeadOID: nil, viewerReviewSubmittedAt: nil,
      hasCurrentApprovalFromOtherReviewer: false, stackPosition: nil, stackSize: nil,
      viewerDidAuthor: author == "demo", mergeState: merge,
      unresolvedConversationCount: number == 94 ? 2 : 0,
      checks: [ .init(name: "Build & test", state: checks, detailsURL: nil),
        .init(name: "Lint", state: .success, detailsURL: nil) ],
      autoMergeEnabled: false, mergeQueuePosition: nil, lifecycleState: .open,
      viewerReviewRequested: author != "demo", checkDetailsComplete: true)
  }
}
