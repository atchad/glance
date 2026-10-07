import XCTest
import Foundation

@testable import Glance

final class PanelWindowTests: XCTestCase {
  @MainActor
  func testMenuBarUsesResizablePanelAndRestoresFrame() throws {
    // SwiftPM's xctest process is not an application bundle. Dashboard startup
    // initializes UserNotifications, which requires one; the CI app runner below
    // executes these same checks without that limitation.
    guard Bundle.main.bundleURL.pathExtension == "app" else {
      throw XCTSkip("Run zsh scripts/test-panel-window.sh for bundled AppKit checks.")
    }
    XCTAssertGreaterThan(try PanelWindowChecks.run(), 0)
  }
}
