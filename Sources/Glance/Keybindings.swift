import Foundation

/// Decode the old preference once when creating the new config file.
enum GlobalShortcut: String, Codable {
  case none, optionSpace, controlSpace, optionG
}

enum GlanceAction: String, CaseIterable, Identifiable, Codable {
  case nextPR, previousPR, firstPR, lastPR, search, clearSearch, openPR, details
  case dismiss, undoDismissal, pin, copyTitle, copyURL, copyBranch
  case snoozeHour, snoozeTomorrow, snoozeWeek, snoozeChanges, snoozeChecks, wake
  case toggleSection, collapseAll, expandAll, refresh, showPanel, hidePanel, togglePanelLevel
  case settings, checkForUpdates, quit

  var id: String { rawValue }

  var title: String {
    switch self {
    case .nextPR: "Next pull request"
    case .previousPR: "Previous pull request"
    case .firstPR: "First pull request"
    case .lastPR: "Last pull request"
    case .search: "Focus search"
    case .clearSearch: "Clear search"
    case .openPR: "Open on GitHub"
    case .details: "Show details"
    case .dismiss: "Dismiss pull request"
    case .undoDismissal: "Undo dismissal"
    case .pin: "Pin or unpin"
    case .copyTitle: "Copy title"
    case .copyURL: "Copy URL"
    case .copyBranch: "Copy branch"
    case .snoozeHour: "Snooze for one hour"
    case .snoozeTomorrow: "Snooze until tomorrow"
    case .snoozeWeek: "Snooze for one week"
    case .snoozeChanges: "Snooze until changes"
    case .snoozeChecks: "Snooze until checks finish"
    case .wake: "Wake pull request"
    case .toggleSection: "Expand or collapse section"
    case .collapseAll: "Collapse all sections"
    case .expandAll: "Expand all sections"
    case .refresh: "Refresh"
    case .showPanel: "Show floating panel"
    case .hidePanel: "Hide Glance"
    case .togglePanelLevel: "Toggle always on top"
    case .settings: "Settings"
    case .checkForUpdates: "Check for updates"
    case .quit: "Quit Glance"
    }
  }

  var defaultBindings: [String] {
    switch self {
    case .nextPR: ["j", "down"]
    case .previousPR: ["k", "up"]
    case .firstPR: ["g g"]
    case .lastPR: ["shift+g"]
    case .search: ["/"]
    case .clearSearch: ["shift+/"]
    case .openPR: ["return"]
    case .details: ["i"]
    case .dismiss: ["d"]
    case .undoDismissal: ["u", "cmd+z"]
    case .pin: ["p"]
    case .copyTitle: ["c t"]
    case .copyURL: ["c u"]
    case .copyBranch: ["c b"]
    case .snoozeHour: ["s h"]
    case .snoozeTomorrow: ["s d"]
    case .snoozeWeek: ["s w"]
    case .snoozeChanges: ["s c"]
    case .snoozeChecks: ["s f"]
    case .wake: ["w"]
    case .toggleSection: ["z z"]
    case .collapseAll: ["z c"]
    case .expandAll: ["z o"]
    case .refresh: ["r"]
    case .showPanel: ["v"]
    case .hidePanel: ["h"]
    case .togglePanelLevel: ["t"]
    case .settings: ["cmd+,"]
    case .checkForUpdates: []
    case .quit: ["cmd+q"]
    }
  }
}

struct KeybindingError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

struct KeyChord: Hashable {
  enum Modifier: String, CaseIterable { case ctrl, alt, shift, cmd }
  let key: String
  let modifiers: Set<Modifier>
  static let namedKeys: Set<String> = Set(["space", "return", "escape", "tab", "up", "down", "left", "right", "home", "end", "pageup", "pagedown", "delete", "forwarddelete"]
    + (1...20).map { "f\($0)" })

  init(_ text: String) throws {
    let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    guard let key = parts.last, Self.namedKeys.contains(key)
      || (key.count == 1 && key.unicodeScalars.allSatisfy { $0.value >= 33 && $0.value <= 126 })
    else { throw KeybindingError(message: "Unknown key in ‘\(text)’.") }
    var modifiers: Set<Modifier> = []
    for part in parts.dropLast() {
      guard let modifier = Modifier(rawValue: part), modifiers.insert(modifier).inserted
      else { throw KeybindingError(message: "Use ctrl, alt, shift, or cmd once per chord: ‘\(text)’.") }
    }
    self.key = key
    self.modifiers = modifiers
  }

  var text: String {
    (Modifier.allCases.filter { modifiers.contains($0) }.map(\.rawValue) + [key]).joined(separator: "+")
  }

  var display: String {
    let symbols: [Modifier: String] = [.ctrl: "⌃", .alt: "⌥", .shift: "⇧", .cmd: "⌘"]
    let keys = ["space": "Space", "return": "↩", "escape": "Esc", "up": "↑", "down": "↓", "left": "←", "right": "→"]
    return Modifier.allCases.filter { modifiers.contains($0) }.compactMap { symbols[$0] }.joined()
      + (keys[key] ?? key.uppercased())
  }
}

struct KeySequence: Hashable {
  let chords: [KeyChord]
  init(_ text: String) throws {
    let parts = text.split(whereSeparator: { $0.isWhitespace })
    guard (1...4).contains(parts.count) else {
      throw KeybindingError(message: "Use one to four chords per binding.")
    }
    chords = try parts.map { try KeyChord(String($0)) }
    guard !chords.contains(where: { $0.key == "escape" || $0.key == "tab" }) else {
      throw KeybindingError(message: "Escape and Tab are reserved for cancel and native focus.")
    }
  }
  var text: String { chords.map(\.text).joined(separator: " ") }
  var display: String { chords.map(\.display).joined(separator: " → ") }
}

/// Only overrides are stored. Missing actions inherit the current defaults; [] disables an action.
struct KeybindingConfiguration: Codable, Equatable {
  var version = 1
  var globalHotkey: String? = "ctrl+shift+space"
  var sequenceTimeout: TimeInterval = 3
  var bindings: [String: [String]] = [:]

  init() {}

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let fields = try decoder.container(keyedBy: Field.self)
    for field in fields.allKeys where CodingKeys(rawValue: field.stringValue) == nil {
      throw KeybindingError(message: "Unknown keybindings field ‘\(field.stringValue)’.")
    }
    version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
    if values.contains(.globalHotkey) {
      globalHotkey = try values.decodeIfPresent(String.self, forKey: .globalHotkey)
    }
    sequenceTimeout = try values.decodeIfPresent(TimeInterval.self, forKey: .sequenceTimeout) ?? 3
    bindings = try values.decodeIfPresent([String: [String]].self, forKey: .bindings) ?? [:]
  }

  private enum CodingKeys: String, CodingKey { case version, globalHotkey, sequenceTimeout, bindings }
  private struct Field: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }

  // Encode null explicitly so a disabled global hotkey does not turn back on after a restart.
  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(version, forKey: .version)
    try values.encode(globalHotkey, forKey: .globalHotkey)
    try values.encode(sequenceTimeout, forKey: .sequenceTimeout)
    try values.encode(bindings, forKey: .bindings)
  }
}

struct ResolvedKeybindings {
  let configuration: KeybindingConfiguration
  let globalHotkey: KeyChord?
  let bindings: [KeySequence: GlanceAction]

  init(_ configuration: KeybindingConfiguration) throws {
    guard configuration.version == 1 else { throw KeybindingError(message: "Unsupported keybindings version.") }
    guard configuration.sequenceTimeout.isFinite, (0.5...30).contains(configuration.sequenceTimeout) else {
      throw KeybindingError(message: "Sequence timeout must be from 0.5 to 30 seconds.")
    }
    for name in configuration.bindings.keys where GlanceAction(rawValue: name) == nil {
      throw KeybindingError(message: "Unknown action ‘\(name)’.")
    }
    let hotkey = try configuration.globalHotkey.map { try KeyChord($0) }
    if let hotkey {
      guard !hotkey.modifiers.intersection([.ctrl, .alt, .cmd]).isEmpty,
        hotkey.key != "escape", hotkey.key != "tab" else {
        throw KeybindingError(message: "The global hotkey needs Control, Option, or Command. Escape and Tab are reserved.")
      }
    }
    var bindings: [KeySequence: GlanceAction] = [:]
    for action in GlanceAction.allCases {
      for text in configuration.bindings[action.rawValue] ?? action.defaultBindings {
        let sequence = try KeySequence(text)
        if sequence.chords.first == hotkey {
          throw KeybindingError(message: "‘\(text)’ conflicts with the global hotkey.")
        }
        for (other, otherAction) in bindings {
          if sequence.chords.starts(with: other.chords) || other.chords.starts(with: sequence.chords) {
            throw KeybindingError(message: "‘\(text)’ for \(action.title) conflicts with ‘\(other.text)’ for \(otherAction.title).")
          }
        }
        bindings[sequence] = action
      }
    }
    self.configuration = configuration
    globalHotkey = hotkey
    self.bindings = bindings
  }

  func sequences(for action: GlanceAction) -> [KeySequence] {
    (configuration.bindings[action.rawValue] ?? action.defaultBindings).compactMap { try? KeySequence($0) }
  }
}

/// The matcher has no window or timer dependency. Callers reset it when focus or bindings change.
struct KeybindingMatcher {
  enum Result: Equatable { case ignored, consumed, action(GlanceAction) }
  private(set) var prefix: [KeyChord] = []
  private(set) var deadline: TimeInterval?

  mutating func reset() { prefix = []; deadline = nil }

  mutating func expire(at now: TimeInterval) {
    if let deadline, now >= deadline { reset() }
  }

  func continuations(in bindings: ResolvedKeybindings, enabled: (GlanceAction) -> Bool) -> [(KeySequence, GlanceAction)] {
    bindings.bindings.filter { $0.key.chords.starts(with: prefix) && enabled($0.value) }
      .map { ($0.key, $0.value) }.sorted { $0.0.text < $1.0.text }
  }

  mutating func handle(_ chord: KeyChord, at now: TimeInterval, bindings: ResolvedKeybindings,
    textEditing: Bool = false, isRepeat: Bool = false, enabled: (GlanceAction) -> Bool = { _ in true }
  ) -> Result {
    expire(at: now)
    guard !textEditing else { reset(); return .ignored }
    if isRepeat {
      guard prefix.isEmpty else { return .consumed }
      guard let action = bindings.bindings.first(where: { $0.key.chords == [chord] })?.value,
        enabled(action) else { return .ignored }
      return action == .nextPR || action == .previousPR ? .action(action) : .consumed
    }
    if chord.key == "escape", !prefix.isEmpty { reset(); return .consumed }
    let wasPending = !prefix.isEmpty
    prefix.append(chord)
    let candidates = continuations(in: bindings, enabled: enabled)
    if let match = candidates.first(where: { $0.0.chords == prefix }) {
      reset()
      return .action(match.1)
    }
    guard !candidates.isEmpty else {
      reset()
      // An invalid continuation cancels, rather than running an unrelated destructive action.
      return wasPending ? .consumed : .ignored
    }
    deadline = now + bindings.configuration.sequenceTimeout
    return .consumed
  }
}
