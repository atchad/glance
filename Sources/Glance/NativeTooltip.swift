import AppKit
import SwiftUI

/// Explicit AppKit tooltip regions survive SwiftUI button-label and scroll-view updates.
struct NativeTooltip: NSViewRepresentable {
  let text: String

  func makeNSView(context: Context) -> Region {
    let view = Region()
    view.setAccessibilityElement(false)
    view.toolTip = text
    return view
  }

  func updateNSView(_ view: Region, context: Context) {
    // Reassigning even an unchanged tooltip can reset an in-progress hover timer.
    if view.toolTip != text { view.toolTip = text }
  }

  final class Region: NSView {
    // Register a tooltip without intercepting the containing row's clicks or context menu.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }
}

extension View {
  func nativeHelp(_ text: String) -> some View {
    background(NativeTooltip(text: text))
      .accessibilityHint(Text(verbatim: text))
  }
}
