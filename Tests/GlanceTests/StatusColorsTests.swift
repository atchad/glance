import AppKit
import SwiftUI
import XCTest

@testable import Glance

final class StatusColorsTests: XCTestCase {
  func testStatusGreenContrastsWithNativeWindowBackgroundInBothAppearances() {
    for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua,
                 .accessibilityHighContrastDarkAqua] {
      NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
        let foreground = NSColor(Color.statusGreen).usingColorSpace(.sRGB)!
        if name == .darkAqua || name == .accessibilityHighContrastDarkAqua {
          let original = NSColor(Color.green).usingColorSpace(.sRGB)!
          XCTAssertEqual(foreground.redComponent, original.redComponent, accuracy: 0.0001)
          XCTAssertEqual(foreground.greenComponent, original.greenComponent, accuracy: 0.0001)
          XCTAssertEqual(foreground.blueComponent, original.blueComponent, accuracy: 0.0001)
        }
        let background = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
        func luminance(_ color: NSColor) -> Double {
          let channels = [color.redComponent, color.greenComponent, color.blueComponent].map {
            $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
          }
          return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        let first = luminance(foreground), second = luminance(background)
        XCTAssertGreaterThanOrEqual((max(first, second) + 0.05) / (min(first, second) + 0.05), 3,
                                    name.rawValue)
      }
    }
  }
}
