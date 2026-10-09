import AppKit
import SwiftUI

/// A native hit target keeps merge clicks separate from the containing SwiftUI row button.
struct PullRequestMergeButton: View {
  let pullRequest: PullRequest
  var isBusy = false
  var error: String? = nil
  let action: () -> Void

  var body: some View {
    let control = PullRequestMergeControl(pullRequest: pullRequest)
    MergeActionTrigger(control: control, isBusy: isBusy, error: error, action: action)
      .frame(width: 20, height: 17)
  }
}

struct MergeActionTrigger: NSViewRepresentable {
  let control: PullRequestMergeControl
  let isBusy: Bool
  let error: String?
  let action: () -> Void

  func makeNSView(context: Context) -> Trigger {
    let button = Trigger()
    button.setButtonType(.momentaryChange)
    button.isBordered = false
    button.title = ""
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleNone
    (button.cell as? NSButtonCell)?.imageDimsWhenDisabled = false
    button.target = button
    button.action = #selector(Trigger.activate)
    updateNSView(button, context: context)
    return button
  }

  func updateNSView(_ button: Trigger, context: Context) {
    button.performAction = action
    button.isEnabled = control.action != nil && !isBusy
    (button.cell as? NSButtonCell)?.imageDimsWhenDisabled = false
    let image = control.icon.image
    image.size = NSSize(width: 12, height: 12)
    button.image = image
    button.contentTintColor = NSColor(control.color)
    button.alphaValue = isBusy ? 0.5 : 1
    let help = isBusy ? (control.action?.progressHelp ?? "Updating pull request…")
      : error.map { "\($0) · \(control.help)" } ?? control.help
    if button.toolTip != help { button.toolTip = help }
    button.setAccessibilityLabel("\(control.pullRequest.repository) #\(control.pullRequest.number): \(help)")
  }

  final class Trigger: NSButton {
    var performAction: (() -> Void)?
    private var handlingPointer = false
    override var acceptsFirstResponder: Bool { isEnabled && !handlingPointer }

    @objc func activate() {
      guard isEnabled else { return }
      performAction?()
    }

    override func mouseDown(with event: NSEvent) {
      // Even inert status icons consume clicks rather than opening/dismissing the row.
      guard isEnabled else { return }
      handlingPointer = true
      if window?.firstResponder === self { window?.makeFirstResponder(nil) }
      defer { handlingPointer = false }
      super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
      guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
        [36, 76, 49].contains(event.keyCode) else { super.keyDown(with: event); return }
      activate()
    }
  }
}
