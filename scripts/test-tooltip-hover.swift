import AppKit
import SwiftUI
import Vision

@testable import Glance

/// Uses a real window and reads the rendered tooltip, not just accessibility metadata.
@main
struct TooltipHoverTestRunner {
  @MainActor
  static func main() {
    UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 2.0])
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let previousApp = NSWorkspace.shared.frontmostApplication
    let previousPointer = CGEvent(source: nil)!.location
    let directory = URL(fileURLWithPath: CommandLine.arguments[1])
    let store = AppStore(
      storageDirectory: directory,
      fetchSnapshots: { sections in
        (
          "fixture",
          sections.map {
            SectionSnapshot(
              id: $0.id,
              pullRequests: (0..<40).map { fixture(id: "PR_\($0)") })
          }
        )
      })
    store.preferences.sections = [PRSection(name: "Tooltip checks", query: "is:pr")]
    store.preferences.notificationsEnabled = false
    // Host the real dashboard without touching the user's persisted panel frame.
    let window = NSPanel(contentRect: NSRect(x: 80, y: 160, width: 410, height: 620),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = NSHostingController(
      rootView: DashboardView(store: store, surface: .panel))
    window.setContentSize(NSSize(width: 410, height: 620))
    app.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    let host = window.contentView!
    Task { @MainActor in
      var succeeded = false
      defer {
        window.orderOut(nil)
        CGWarpMouseCursorPosition(previousPointer)
        previousApp?.activate(options: [])
        exit(succeeded ? EXIT_SUCCESS : EXIT_FAILURE)
      }
      do {
        try await Task.sleep(for: .seconds(1))
        // Centers of the fixed 11pt metadata slots; nil targets the native Details control.
        let probes: [(CGFloat?, String)] = [
          (18.5, "Approved"), (33.5, "Checks failed"),
          (51.5, "Fix failing checks"), (nil, "Read full title and fetched checks (I)"),
        ]
        for phase in ["initial", "reopened", "refreshed"] {
          if phase == "reopened" {
            window.orderOut(nil)
            try await Task.sleep(for: .milliseconds(500))
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(500))
          }
          if phase == "refreshed" {
            store.refresh()
            while store.isRefreshing { try await Task.sleep(for: .milliseconds(50)) }
            try await Task.sleep(for: .milliseconds(500))
          }
          for (x, expected) in probes {
            movePointer(to: CGPoint(x: 0, y: 0))
            try await Task.sleep(for: .milliseconds(300))
            guard let trigger = detailTrigger(in: host) else {
              throw Failure(message: "Dashboard row did not load.")
            }
            let anchor = trigger.convert(
              NSPoint(x: trigger.bounds.midX, y: trigger.bounds.midY), to: nil)
            let pointInWindow = NSPoint(
              x: x.map { host.convert(.zero, to: nil).x + $0 } ?? anchor.x, y: anchor.y)
            let screen = window.convertPoint(toScreen: pointInWindow)
            let target = CGPoint(x: screen.x, y: NSScreen.screens[0].frame.height - screen.y)
            movePointer(to: target)
            var actual = ""
            for _ in 0..<30 {
              try await Task.sleep(for: .milliseconds(150))
              guard window.isVisible && window.isKeyWindow && app.isActive else {
                throw Failure(
                  message:
                    "Dashboard lost focus. Leave the mouse and keyboard idle during this check.")
              }
              let pointer = CGEvent(source: nil)!.location
              guard abs(pointer.x - target.x) < 2 && abs(pointer.y - target.y) < 2 else {
                throw Failure(
                  message: "Pointer moved during the hover check. Please rerun without interacting."
                )
              }
              if let tooltip = app.windows.first(where: {
                $0.isVisible && String(describing: type(of: $0)) == "NSToolTipPanel"
              }) {
                actual = try caption(of: tooltip)
              }
              if actual == expected { break }
            }
            guard actual == expected else {
              throw Failure(message: "Expected ‘\(expected)’, got ‘\(actual)’.")
            }
            print("Passed \(phase) hover caption: \(expected)")
          }
        }
        succeeded = true
      } catch {
        fputs("FAILED: \(error.localizedDescription)\n", stderr)
      }
    }
    app.run()
  }

  @MainActor private static func movePointer(to point: CGPoint) {
    CGEvent(
      mouseEventSource: nil, mouseType: .mouseMoved,
      mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
  }

  @MainActor private static func caption(of tooltip: NSWindow) throws -> String {
    guard let view = tooltip.contentView,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { throw Failure(message: "Cannot render tooltip.") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let image = bitmap.cgImage else { throw Failure(message: "Cannot render tooltip.") }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: image).perform([request])
    return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
      ?? ""
  }

  @MainActor private static func detailTrigger(in view: NSView) -> DetailActionButton.Trigger? {
    if let trigger = view as? DetailActionButton.Trigger { return trigger }
    return view.subviews.compactMap { detailTrigger(in: $0) }.first
  }

  private struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  private static func fixture(id: String = "PR_1") -> PullRequest {
    PullRequest(
      id: id, number: 1, repository: "owner/repo", title: "Tooltip regression fixture",
      author: "author", authorAvatarURL: nil,
      url: URL(string: "https://github.com/owner/repo/pull/1")!,
      branch: "feature", headRefOID: "abc", createdAt: .now, reviewRequestedAt: nil,
      updatedAt: .now, isDraft: false, reviewDecision: "APPROVED", checksState: .failure,
      additions: 1, deletions: 0, labels: [], requestedReviewers: [], viewerReviewState: nil,
      viewerReviewedHeadOID: nil, viewerReviewSubmittedAt: nil,
      hasCurrentApprovalFromOtherReviewer: false, stackPosition: nil, stackSize: nil,
      viewerDidAuthor: true, mergeState: .clean, unresolvedConversationCount: 0, checks: nil,
      autoMergeEnabled: false, mergeQueuePosition: nil, lifecycleState: .open,
      viewerReviewRequested: false)
  }
}
