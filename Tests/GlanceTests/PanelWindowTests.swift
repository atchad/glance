import XCTest
import Foundation
import AppKit

@testable import Glance

final class PanelWindowTests: XCTestCase {
  @MainActor
  func testResizeTargetsFitSmallScreensIncludingWindowChrome() {
    let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 410, height: 620),
      styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.contentMinSize = NSSize(width: 310, height: 320)
    for availableHeight: CGFloat in [400, 550, 720, 1000] {
      let visibleFrame = NSRect(x: 0, y: 0, width: 1024, height: availableHeight)
      let heights = PanelWindowChecks.resizeHeights(for: window, visibleFrame: visibleFrame)
      XCTAssertEqual(heights.count, 3)
      XCTAssertGreaterThan(Set(heights).count, 1, "Exercise distinct resize targets on small screens.")
      for height in heights {
        XCTAssertGreaterThanOrEqual(height, window.contentMinSize.height)
        let outerFrame = window.frameRect(forContentRect:
          NSRect(x: 0, y: 0, width: 410, height: height))
        XCTAssertLessThanOrEqual(outerFrame.height, availableHeight,
          "AppKit must not need to clamp a requested resize on a \(availableHeight)pt screen.")
      }
    }
  }

  @MainActor
  func testMenuBarUsesPopoverAndFloatingPanelRestoresFrame() throws {
    // SwiftPM's xctest process is not an application bundle. Dashboard startup
    // initializes UserNotifications, which requires one; the CI app runner below
    // executes these same checks without that limitation.
    guard Bundle.main.bundleURL.pathExtension == "app" else {
      throw XCTSkip("Run zsh scripts/test-panel-window.sh for bundled AppKit checks.")
    }
    XCTAssertGreaterThan(try PanelWindowChecks.run(), 0)
  }
}
