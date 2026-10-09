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

  private let groups: [(String, [GlanceAction])] = [
    ("Navigation", [.nextPR, .previousPR, .firstPR, .lastPR, .search, .clearSearch]),
    ("Pull requests", [.openPR, .details, .dismiss, .undoDismissal, .pin, .copyTitle, .copyURL, .copyBranch]),
    ("Snoozing", [.snoozeHour, .snoozeTomorrow, .snoozeWeek, .snoozeChanges, .snoozeChecks, .wake]),
    ("Sections", [.toggleSection, .collapseAll, .expandAll]),
    ("Glance", [.refresh, .showPanel, .hidePanel, .togglePanelLevel, .settings, .checkForUpdates, .quit]),
  ]

  private func matches(_ action: GlanceAction) -> Bool {
    search.isEmpty || action.title.localizedCaseInsensitiveContains(search)
      || action.rawValue.localizedCaseInsensitiveContains(search)
      || keys.label(for: action).localizedCaseInsensitiveContains(search)
  }

  var body: some View {
    VStack(spacing: 0) {
      SettingsForm {
        SettingsGroup {
          LabeledContent("Show or hide Glance") {
            Text(keys.resolved.globalHotkey?.display ?? "Off")
              .font(.body.monospaced())
            Button("Edit…") { editing = .global }
              .accessibilityLabel("Edit global shortcut")
          }
          .accessibilityElement(children: .contain)
        } header: {
          Text("Global shortcut")
        } footer: {
          SettingsDescription("Show Glance from any app. Press again to hide it when it has focus.")
        }
        ForEach(groups, id: \.0) { title, actions in
          let filtered = actions.filter(matches)
          if !filtered.isEmpty {
            SettingsGroup {
              ForEach(filtered) { action in
                LabeledContent(action.title) {
                  Button { editing = .action(action) } label: {
                    Text(keys.label(for: action).isEmpty ? "Add shortcut" : keys.label(for: action))
                      .font(.body.monospaced()).foregroundStyle(.secondary)
                      .multilineTextAlignment(.trailing)
                      .frame(minWidth: 64, alignment: .trailing)
                      .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .help("Edit shortcut")
                  .accessibilityValue(keys.label(for: action).isEmpty ? "Unbound" : keys.label(for: action))
                  .accessibilityLabel("Edit keys for \(action.title)")
                }
                .accessibilityElement(children: .contain)
              }
            } header: {
              VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if title == "Navigation" {
                  SettingsDescription("Click a shortcut to edit it. Applies while Glance has focus.")
                }
              }
            }
            .compactRows()
          }
        }
        if !GlanceAction.allCases.contains(where: matches) {
          SettingsGroup { Text("No shortcuts found").foregroundStyle(.secondary) }
        }
        SettingsGroup {
          Stepper(value: Binding(get: { keys.resolved.configuration.sequenceTimeout },
            set: { value in keys.edit { $0.sequenceTimeout = value } }), in: 0.5...30, step: 0.5) {
            HStack {
              Text("Time between keys")
              Spacer()
              Text("\(keys.resolved.configuration.sequenceTimeout.formatted()) seconds")
                .monospacedDigit().foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
          }
          .accessibilityLabel("Time between keys")
        } header: {
          HStack {
            Text("Key sequences")
            SettingsHelpButton(title: "Key sequences",
              message: "Press a bound key while the dashboard has focus; no leader key is needed. A prefix shows the next available keys. Escape cancels the sequence. Text fields and native controls keep their usual keys. The timeout controls how long you can pause between sequence keys.")
          }
        }
        if let error = keys.errorMessage ?? keys.registrationError {
          SettingsGroup { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
        }
      }
      .toolbar {
        ToolbarItem(placement: .automatic) {
          SettingsSearchField(text: $search)
            .frame(width: 180)
        }
      }
      Divider()
      HStack {
        Menu("Advanced") {
          Button("Reveal Configuration File") { keys.revealFile() }
          Button("Reload Configuration") { keys.reload() }
        }
        .fixedSize()
        Spacer()
        Button("Reset All…") { confirmReset = true }
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
      HStack {
        Text(title).font(.headline)
        SettingsHelpButton(title: "Shortcut format",
          message: "Separate alternative shortcuts with a semicolon (c u; cmd+shift+u). Separate sequence keys with a space (c u). Use ctrl, alt, shift, and cmd for modifiers. You can also record keys instead of typing them.")
      }
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
          .keyboardShortcut(.cancelAction)
        Button("Save") { save() }.disabled(recording)
          .keyboardShortcut(.defaultAction)
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
