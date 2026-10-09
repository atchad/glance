import AppKit
import SwiftUI

/// An explicitly keyboard-focusable native button, including when macOS Keyboard Navigation is off.
struct DetailActionButton: NSViewRepresentable {
  let label: String
  var title: String? = nil
  let focusRequest: Int
  var isShowingDetails = false
  var keyboardPresentation = false
  var restoresFocusOnlyForKeyboard = false
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
    if isShowingDetails && !button.isShowingDetails {
      // Dashboard bindings can open details without invoking this button's keyDown.
      button.restoresKeyboardFocus = keyboardPresentation || button.restoresKeyboardFocus
    }
    button.isShowingDetails = isShowingDetails
    button.setAccessibilityLabel(label)
    button.toolTip = help
    if button.focusRequest != focusRequest {
      button.focusRequest = focusRequest
      let keyboardRestoration = button.consumeKeyboardFocusRestoration()
      let shouldRestoreFocus = !restoresFocusOnlyForKeyboard || keyboardRestoration
      // Popover dismissal returns key status to the containing window asynchronously.
      DispatchQueue.main.async { [weak button] in
        guard let button, !button.isShowingDetails,
          let window = button.window else { return }
        if shouldRestoreFocus {
          window.makeFirstResponder(button)
        } else if window.firstResponder === button {
          // AppKit may restore the popover anchor on its own after pointer activation.
          window.makeFirstResponder(nil)
        }
      }
    }
  }

  final class Trigger: NSButton {
    var performAction: (() -> Void)?
    var focusRequest = 0
    private var handlingPointer = false
    var restoresKeyboardFocus = false
    var isShowingDetails = false
    override var acceptsFirstResponder: Bool { !handlingPointer }

    override func mouseDown(with event: NSEvent) {
      restoresKeyboardFocus = false
      handlingPointer = true
      // Pointer activation must not leave a keyboard ring or steal dashboard key routing.
      if window?.firstResponder === self { window?.makeFirstResponder(nil) }
      defer { handlingPointer = false }
      super.mouseDown(with: event)
    }

    @objc func activate() { performAction?() }

    func consumeKeyboardFocusRestoration() -> Bool {
      defer { restoresKeyboardFocus = false }
      return restoresKeyboardFocus
    }

    override func keyDown(with event: NSEvent) {
      if !handleDetailKey(event) { super.keyDown(with: event) }
    }

    @discardableResult
    func handleDetailKey(_ event: NSEvent) -> Bool {
      guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
      else { return false }
      if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 {
        restoresKeyboardFocus = true
        activate()
      } else {
        return false
      }
      return true
    }
  }
}
