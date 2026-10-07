import AppKit
import SwiftUI

/// An explicitly keyboard-focusable native button, including when macOS Keyboard Navigation is off.
struct DetailActionButton: NSViewRepresentable {
  let label: String
  var title: String? = nil
  let focusRequest: Int
  var help: String? = nil
  let action: () -> Void

  func makeNSView(context: Context) -> Trigger {
    let button = Trigger()
    button.isBordered = title != nil
    button.bezelStyle = .rounded
    button.title = title ?? ""
    button.image = title == nil ? NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil) : nil
    button.imagePosition = title == nil ? .imageOnly : .noImage
    button.contentTintColor = title == nil ? .secondaryLabelColor : .labelColor
    button.target = button
    button.action = #selector(Trigger.activate)
    updateNSView(button, context: context)
    return button
  }

  func updateNSView(_ button: Trigger, context: Context) {
    button.performAction = action
    button.setAccessibilityLabel(label)
    button.toolTip = help
    if button.focusRequest != focusRequest {
      button.focusRequest = focusRequest
      // Popover dismissal returns key status to the containing window asynchronously.
      DispatchQueue.main.async { [weak button] in
        guard let button, let window = button.window else { return }
        window.makeFirstResponder(button)
      }
    }
  }

  final class Trigger: NSButton {
    var performAction: (() -> Void)?
    var focusRequest = 0
    override var acceptsFirstResponder: Bool { true }

    @objc func activate() { performAction?() }

    override func keyDown(with event: NSEvent) {
      if !handleDetailKey(event) { super.keyDown(with: event) }
    }

    @discardableResult
    func handleDetailKey(_ event: NSEvent) -> Bool {
      guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
      else { return false }
      if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 {
        activate()
      } else {
        return false
      }
      return true
    }
  }
}
