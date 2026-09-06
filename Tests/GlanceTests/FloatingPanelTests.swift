import AppKit
import XCTest

@testable import Glance

final class FloatingPanelTests: XCTestCase {
  @MainActor
  func testTitlebarPreferenceDispatchesNativeActions() {
    let panel = ActionPanel()
    FloatingPanelController.performTitleBarAction(for: panel, preference: "None", fill: { panel.actions.append("fill") })
    XCTAssertEqual(panel.actions, [])
    FloatingPanelController.performTitleBarAction(for: panel, preference: "Minimize", fill: { panel.actions.append("fill") })
    FloatingPanelController.performTitleBarAction(for: panel, preference: "Maximize", fill: { panel.actions.append("fill") })
    FloatingPanelController.performTitleBarAction(for: panel, preference: nil, fill: { panel.actions.append("fill") })
    FloatingPanelController.performTitleBarAction(for: panel, preference: "Fill", fill: { panel.actions.append("fill") })
    FloatingPanelController.performTitleBarAction(for: panel, preference: "Zoom", fill: { panel.actions.append("fill") })
    XCTAssertEqual(panel.actions, ["minimize", "zoom", "zoom", "fill", "zoom"])
  }

  func testRestoredFrameThatFitsKeepsUserSizeAndPosition() {
    let frame = NSRect(x: -1100, y: 120, width: 530, height: 740)
    let screen = NSRect(x: -1440, y: 25, width: 1440, height: 875)
    XCTAssertEqual(FloatingPanelController.constrainedFrame(frame, to: screen), frame)
  }

  func testPartiallyOffscreenFrameMovesInsideWithoutResizing() {
    let screen = NSRect(x: 0, y: 25, width: 1440, height: 875)
    XCTAssertEqual(
      FloatingPanelController.constrainedFrame(
        NSRect(x: 1300, y: 800, width: 410, height: 642), to: screen),
      NSRect(x: 1030, y: 258, width: 410, height: 642))
    XCTAssertEqual(
      FloatingPanelController.constrainedFrame(
        NSRect(x: -100, y: -50, width: 410, height: 642), to: screen),
      NSRect(x: 0, y: 25, width: 410, height: 642))
  }

  func testOversizedRestoredFrameFitsSmallerScreen() {
    let screen = NSRect(x: 100, y: 25, width: 800, height: 600)
    XCTAssertEqual(
      FloatingPanelController.constrainedFrame(
        NSRect(x: 200, y: 100, width: 1200, height: 900), to: screen), screen)
  }
}

@MainActor
private final class ActionPanel: NSPanel {
  var actions: [String] = []
  override func miniaturize(_ sender: Any?) { actions.append("minimize") }
  override func performZoom(_ sender: Any?) { actions.append("zoom") }
}
