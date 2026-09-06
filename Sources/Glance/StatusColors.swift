import AppKit
import SwiftUI

extension Color {
  // System green is too light for small status symbols on light materials.
  static let statusGreen = Color(nsColor: NSColor(name: nil) { appearance in
    var color = NSColor(Color.green)
    appearance.performAsCurrentDrawingAppearance {
      if appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua {
        color = color.blended(withFraction: 0.45, of: .labelColor) ?? color
      }
    }
    return color
  })
}
