import AppKit
import SwiftUI

private enum BindingEditorTarget: Identifiable {
  case global, action(GlanceAction)
  var id: String { switch self { case .global: "global"; case .action(let action): action.rawValue } }
}

struct KeyboardSettingsPage: View {
  @ObservedObject var keys: KeybindingStore
  @State private var search = ""
  @State private var editing: BindingEditorTarget?
  @State private var confirmReset = false

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section("Global hotkey") {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text("Show or hide Glance")
              Text("Show and focus the panel. Hide it only when it already has focus.")
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(keys.resolved.globalHotkey?.display ?? "Off").font(.body.monospaced())
            Button("Edit…") { editing = .global }
          }
        }
        Section("Sequences") {
          Stepper(value: Binding(get: { keys.resolved.configuration.sequenceTimeout },
            set: { value in keys.edit { $0.sequenceTimeout = value } }), in: 0.5...30, step: 0.5) {
            LabeledContent("Timeout", value: "\(keys.resolved.configuration.sequenceTimeout.formatted()) seconds")
          }
          Text("No leader key. Press a bound key when the dashboard has focus. Prefixes show the next keys. Escape cancels. Text fields and native controls keep their keys.")
            .font(.caption).foregroundStyle(.secondary)
        }
        if let error = keys.errorMessage ?? keys.registrationError {
          Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
        }
      }
      .formStyle(.grouped)
      TextField("Find an action or key", text: $search)
        .textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.bottom, 8)
      List(GlanceAction.allCases.filter {
        search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
          || $0.rawValue.localizedCaseInsensitiveContains(search) || keys.label(for: $0).localizedCaseInsensitiveContains(search)
      }) { action in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(action.title)
            Text(action.rawValue).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Text(keys.label(for: action).isEmpty ? "Unbound" : keys.label(for: action))
            .font(.caption.monospaced()).foregroundStyle(.secondary)
          Button("Edit…") { editing = .action(action) }
            .accessibilityLabel("Edit keys for \(action.title)")
        }
        .padding(.vertical, 3)
      }
      .listStyle(.inset)
      Divider()
      HStack {
        Button("Reveal config file") { keys.revealFile() }
        Button("Reload") { keys.reload() }
        Spacer()
        Button("Reset all…") { confirmReset = true }
      }.padding(16)
    }
    .sheet(item: $editing) { target in BindingEditor(keys: keys, target: target) }
    .confirmationDialog("Reset all keybindings and the global hotkey?", isPresented: $confirmReset) {
      Button("Reset to defaults", role: .destructive) { keys.reset() }
    }
  }
}

private struct BindingEditor: View {
  @ObservedObject var keys: KeybindingStore
  let target: BindingEditorTarget
  @Environment(\.dismiss) private var dismiss
  @State private var text: String
  @State private var recording = false
  @State private var recorded: [KeyChord] = []
  private let original: KeybindingConfiguration

  init(keys: KeybindingStore, target: BindingEditorTarget) {
    self.keys = keys
    self.target = target
    original = keys.resolved.configuration
    let text: String
    switch target {
    case .global: text = keys.resolved.configuration.globalHotkey ?? ""
    case .action(let action): text = keys.resolved.sequences(for: action).map(\.text).joined(separator: "; ")
    }
    _text = State(initialValue: text)
  }

  private var title: String {
    switch target { case .global: "Show or hide Glance"; case .action(let action): action.title }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title).font(.headline)
      Text("Separate alternative bindings with a semicolon. Separate sequence keys with a space. Use ctrl, alt, shift, and cmd for modifiers.")
        .font(.callout).foregroundStyle(.secondary)
      TextField("For example: c u; cmd+shift+u", text: $text)
        .textFieldStyle(.roundedBorder).font(.body.monospaced()).disabled(recording)
      HStack {
        Button(recording ? "Finish recording" : "Record keys") {
          if recording { finishRecording() } else {
            recorded = []
            keys.isRecording = true
            recording = true
          }
        }
        if recording {
          Text(recorded.isEmpty ? "Press keys. Escape cancels." : recorded.map(\.display).joined(separator: " → "))
            .font(.caption.monospaced())
          ShortcutRecorder { event in
            guard let chord = KeyChord(event: event), !event.isARepeat else { return }
            if chord.key == "escape" { stopRecording(); return }
            if chord.key == "tab" { return }
            switch target {
            case .global: recorded = [chord]; finishRecording()
            case .action:
              if recorded.count < 4 { recorded.append(chord) }
            }
          }
          .frame(width: 1, height: 1).accessibilityLabel("Shortcut recorder")
        }
      }
      if let error = keys.errorMessage {
        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
      }
      HStack {
        if case .action(let action) = target {
          Button("Use defaults") { text = action.defaultBindings.joined(separator: "; ") }
        }
        Button("Disable") { text = "" }.disabled(recording)
        Spacer()
        Button("Cancel") { stopRecording(); dismiss() }
        Button("Save") { save() }.disabled(recording)
      }
    }
    .padding(24).frame(width: 540)
    .onDisappear { stopRecording() }
  }

  private func stopRecording() { recording = false; keys.isRecording = false }

  private func finishRecording() {
    let binding = recorded.map(\.text).joined(separator: " ")
    if !binding.isEmpty {
      switch target {
      case .global: text = binding
      case .action: text = text.isEmpty ? binding : text + "; " + binding
      }
    }
    stopRecording()
  }

  private func save() {
    let success = keys.edit(expected: original) { configuration in
      switch target {
      case .global:
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.globalHotkey = value.isEmpty ? nil : value
      case .action(let action):
        let values = text.split(separator: ";", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if values == action.defaultBindings { configuration.bindings.removeValue(forKey: action.rawValue) }
        else { configuration.bindings[action.rawValue] = values }
      }
    }
    if success { dismiss() }
  }
}

private struct ShortcutRecorder: NSViewRepresentable {
  let receive: (NSEvent) -> Void
  func makeNSView(context: Context) -> Recorder {
    let view = Recorder()
    view.receive = receive
    return view
  }
  func updateNSView(_ view: Recorder, context: Context) { view.receive = receive }

  final class Recorder: NSView {
    var receive: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.window?.makeFirstResponder(self)
      }
    }
    override func keyDown(with event: NSEvent) { receive?(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      guard window?.firstResponder === self else { return false }
      receive?(event)
      return true
    }
  }
}
