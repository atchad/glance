import AppKit
import SwiftUI
import XCTest
@testable import Glance

@MainActor
final class NativeTooltipTests: XCTestCase {
  func testTooltipRegionDoesNotInterceptRowClicks() {
    let view = NativeTooltip.Region(frame: NSRect(x: 0, y: 0, width: 11, height: 11))
    XCTAssertNil(view.hitTest(NSPoint(x: 5.5, y: 5.5)))
    XCTAssertFalse(view.acceptsFirstResponder)
  }

  func testCaptionUpdatesReuseTheNativeRegion() throws {
    let host = NSHostingView(rootView: Fixture(caption: "Fix 2 failing checks"))
    _ = host.fittingSize
    host.layoutSubtreeIfNeeded()
    let original = try XCTUnwrap(region(in: host))
    XCTAssertEqual(original.toolTip, "Fix 2 failing checks")
    host.rootView = Fixture(caption: "Fix 3 failing checks")
    host.layoutSubtreeIfNeeded()
    XCTAssertTrue(region(in: host) === original)
    XCTAssertEqual(original.toolTip, "Fix 3 failing checks")
  }

  private struct Fixture: View {
    let caption: String
    var body: some View {
      Image(systemName: "exclamationmark.circle.fill")
        .frame(width: 11, height: 11)
        .nativeHelp(caption)
    }
  }

  private func region(in view: NSView) -> NativeTooltip.Region? {
    if let view = view as? NativeTooltip.Region { return view }
    return view.subviews.compactMap { region(in: $0) }.first
  }
}
