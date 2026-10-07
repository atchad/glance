import AppKit
import SwiftUI

/// An opaque sRGB color, persisted independently of PRs and their cache lifetime.
struct RepositoryColor: Equatable, Hashable {
  let hex: String

  init?(hex: String) {
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
    self.hex = "#" + digits.uppercased()
  }

  init?(color: Color) {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
    guard components.allSatisfy(\.isFinite) else { return nil }
    self.init(hex: String(format: "#%02X%02X%02X",
      arguments: components.map { Int((min(1, max(0, $0)) * 255).rounded()) }))
  }

  var color: Color { Self.swiftUIColor(hex: hex) }

  /// Presets retain their hue but brighten in dark mode; custom colors stay exact.
  func displayColor(for scheme: ColorScheme) -> Color {
    guard scheme == .dark, let preset = Self.presets.first(where: { $0.color == self }) else {
      return color
    }
    return Self.swiftUIColor(hex: preset.darkHex)
  }

  private static func swiftUIColor(hex: String) -> Color {
    let rgb = UInt32(hex.dropFirst(), radix: 16)!
    return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
      green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
  }

  struct Preset: Identifiable {
    let name: String
    let color: RepositoryColor
    let darkHex: String
    var id: String { color.hex }
  }

  // Interleave warm/cool hues so adjacent assignments are easy to tell apart.
  static let presets: [Preset] = [
    Preset(name: "Blue", color: RepositoryColor(hex: "#0072B2")!, darkHex: "#56B4E9"),
    Preset(name: "Orange", color: RepositoryColor(hex: "#B85C00")!, darkHex: "#F5A348"),
    Preset(name: "Teal", color: RepositoryColor(hex: "#008576")!, darkHex: "#4CCAB5"),
    Preset(name: "Rose", color: RepositoryColor(hex: "#C03D65")!, darkHex: "#F582A2"),
    Preset(name: "Violet", color: RepositoryColor(hex: "#8054B3")!, darkHex: "#BA9BE8"),
    Preset(name: "Gold", color: RepositoryColor(hex: "#8F7300")!, darkHex: "#DCC45B"),
    Preset(name: "Slate", color: RepositoryColor(hex: "#637182")!, darkHex: "#B0BAC7"),
    Preset(name: "Vermilion", color: RepositoryColor(hex: "#BD482E")!, darkHex: "#F68D70"),
    Preset(name: "Magenta", color: RepositoryColor(hex: "#A33C96")!, darkHex: "#E38BD5"),
    Preset(name: "Green", color: RepositoryColor(hex: "#547B28")!, darkHex: "#A1C967"),
  ]
}

extension Preferences {
  func repositoryColor(for repository: String) -> RepositoryColor? {
    repositoryColors[repository.lowercased()]
  }

  mutating func assignRepositoryColors(for repositories: [String]) {
    // Sorting each new batch makes assignments independent of section/dictionary order.
    for repository in Set(repositories.map { $0.lowercased() }).sorted() {
      guard repositoryColors[repository] == nil else { continue }
      repositoryColors[repository] = RepositoryColor.presets[
        repositoryColors.count % RepositoryColor.presets.count].color
    }
  }
}
