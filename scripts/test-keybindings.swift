import AppKit
import Carbon
import Foundation

/// Runs without XCTest so the keyboard module can be checked with Command Line Tools.
@main
struct KeybindingTests {
  @MainActor
  static func main() {
    do { try run() } catch {
      fputs("\(error.localizedDescription)\n", stderr)
      exit(EXIT_FAILURE)
    }
  }

  @MainActor
  static func run() throws {
    var checks = 0
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
      checks += 1
      guard try condition() else { throw KeybindingError(message: "FAILED: \(message)") }
    }
    func rejects(_ configuration: KeybindingConfiguration, _ message: String) throws {
      var rejected = false
      do { _ = try ResolvedKeybindings(configuration) } catch { rejected = true }
      try check(rejected, message)
    }
    let defaults = try ResolvedKeybindings(KeybindingConfiguration())
    try check(defaults.globalHotkey?.text == "ctrl+shift+space", "default global hotkey")
    try check(defaults.bindings.count == 32, "all default alternatives compile")
    try check(try KeyChord("SHIFT+CTRL+space") == KeyChord("ctrl+shift+space"), "modifier order and case")
    let global = try KeyChord("ctrl+shift+space")
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .shift],
      timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
    try check(KeyChord(event: event) == global, "native events preserve Control and Shift")
    try check(global.eventModifiers == [.control, .shift], "menu modifiers agree with matcher")
    try check(try KeyChord("f1").carbonKeyCode == 122, "function keys can be global hotkeys")
    try check(try KeyChord("f20").keyEquivalent == String(UnicodeScalar(0xf717)!), "function-key menu equivalents")
    var config = KeybindingConfiguration()
    config.bindings["dismiss"] = ["p"]
    try rejects(config, "duplicate action binding")
    config.bindings["dismiss"] = ["c"]
    try rejects(config, "short binding conflicts with an existing prefix")
    config.bindings["dismiss"] = ["r x"]
    try rejects(config, "long binding conflicts with an existing action")
    config.bindings["dismiss"] = ["ctrl+shift+space"]
    try rejects(config, "local and global conflict")
    config.bindings["dismiss"] = ["escape"]
    try rejects(config, "Escape stays reserved")
    config.bindings["dismiss"] = ["tab"]
    try rejects(config, "Tab stays reserved")
    config.bindings["dismiss"] = ["ctrl+ctrl+a"]
    try rejects(config, "duplicate modifiers")
    config.bindings["dismiss"] = ["nonsense"]
    try rejects(config, "unknown key")
    config.bindings = ["typo": []]
    try rejects(config, "unknown action")
    config.bindings = [:]
    for timeout in [0.0, 0.49, 30.01, Double.infinity, Double.nan] {
      config.sequenceTimeout = timeout
      try rejects(config, "invalid timeout")
    }
    config = KeybindingConfiguration()
    config.version = 2
    try rejects(config, "unknown version")
    config.version = 1
    config.globalHotkey = "shift+a"
    try rejects(config, "global needs a non-Shift modifier")
    config.globalHotkey = nil
    config.bindings["dismiss"] = []
    let disabled = try ResolvedKeybindings(config)
    try check(disabled.globalHotkey == nil, "global can be disabled")
    try check(disabled.sequences(for: .dismiss).isEmpty, "action can be disabled")
    let roundTrip = try JSONDecoder().decode(KeybindingConfiguration.self, from: JSONEncoder().encode(config))
    try check(roundTrip == config, "disabled global persists as null")
    try check(try JSONDecoder().decode(KeybindingConfiguration.self, from: Data("{}".utf8)) == KeybindingConfiguration(), "missing fields use defaults")
    var unknownRejected = false
    do { _ = try JSONDecoder().decode(KeybindingConfiguration.self, from: Data("{\"typo\":1}".utf8)) } catch { unknownRejected = true }
    try check(unknownRejected, "unknown top-level fields are rejected")

    var matcher = KeybindingMatcher()
    try check(matcher.handle(KeyChord("j"), at: 0, bindings: defaults) == .action(.nextPR), "direct action")
    try check(matcher.handle(KeyChord("p"), at: 0, bindings: defaults, isRepeat: true) == .consumed, "holding a key cannot repeat pin/dismiss actions")
    try check(matcher.handle(KeyChord("j"), at: 0, bindings: defaults, isRepeat: true) == .action(.nextPR), "holding a custom navigation key can repeat navigation")
    try check(matcher.handle(KeyChord("a"), at: 0, bindings: defaults, textEditing: true, isRepeat: true) == .ignored, "held text keys stay native")
    try check(matcher.handle(KeyChord("c"), at: 0, bindings: defaults) == .consumed, "prefix starts")
    try check(matcher.continuations(in: defaults, enabled: { _ in true }).count == 3, "copy hints")
    try check(matcher.handle(KeyChord("u"), at: 1, bindings: defaults) == .action(.copyURL), "sequence completes")
    try check(matcher.prefix.isEmpty, "completed sequence resets")
    _ = matcher.handle(try KeyChord("c"), at: 0, bindings: defaults)
    try check(matcher.handle(KeyChord("d"), at: 1, bindings: defaults) == .consumed, "invalid continuation does not dismiss")
    _ = matcher.handle(try KeyChord("c"), at: 0, bindings: defaults)
    try check(matcher.handle(KeyChord("escape"), at: 1, bindings: defaults) == .consumed && matcher.prefix.isEmpty, "Escape cancels")
    _ = matcher.handle(try KeyChord("c"), at: 0, bindings: defaults)
    matcher.expire(at: 3)
    try check(matcher.prefix.isEmpty, "timeout clears hints without another key")
    _ = matcher.handle(try KeyChord("c"), at: 0, bindings: defaults)
    try check(matcher.handle(KeyChord("u"), at: 3, bindings: defaults) == .action(.undoDismissal), "expired prefix does not run copy")
    _ = matcher.handle(try KeyChord("c"), at: 0, bindings: defaults)
    try check(matcher.handle(KeyChord("d"), at: 1, bindings: defaults, textEditing: true) == .ignored && matcher.prefix.isEmpty, "editor keeps destructive keys and resets prefix")
    try check(matcher.handle(KeyChord("c"), at: 0, bindings: defaults, enabled: { _ in false }) == .ignored, "unavailable prefix is not consumed")
    try check(matcher.handle(KeyChord("d"), at: 0, bindings: defaults, enabled: { $0 != .dismiss }) == .ignored, "no action on missing selection")
    config = KeybindingConfiguration()
    config.bindings["dismiss"] = ["x"]
    let custom = try ResolvedKeybindings(config)
    try check(matcher.handle(KeyChord("d"), at: 0, bindings: custom) == .ignored, "old direct key removed after rebind")
    try check(matcher.handle(KeyChord("x"), at: 0, bindings: custom) == .action(.dismiss), "custom direct key dispatches")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Glance-keybindings-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("keybindings.json")
    let store = KeybindingStore(url: url, watch: false)
    try check(store.errorMessage == nil && FileManager.default.fileExists(atPath: url.path), "first launch creates config")
    try check(store.edit { $0.bindings["dismiss"] = ["x"] }, "Settings writes shared file")
    let saved = try Data(contentsOf: url)
    try Data("{\"bindings\":{\"dismiss\":[\"p\"]}}".utf8).write(to: url, options: .atomic)
    store.reload()
    try check(store.errorMessage != nil && store.resolved.sequences(for: .dismiss).first?.text == "x", "invalid external edit retains last good config")
    try check(!store.edit { $0.globalHotkey = nil }, "Settings does not overwrite an invalid external file")
    try check(try Data(contentsOf: url) != saved, "invalid external file is preserved")
    try saved.write(to: url, options: .atomic)
    store.reload()
    try check(store.errorMessage == nil, "corrected external edit clears error")
    try FileManager.default.removeItem(at: url)
    store.reload()
    try check(store.errorMessage != nil, "removed config is reported")
    try saved.write(to: url, options: .atomic)
    store.reload()
    try check(store.errorMessage == nil, "restoring identical config clears missing-file error")
    try check(!store.edit { $0.bindings["dismiss"] = ["p"] }, "Settings rejects a conflict")
    try check(store.edit { $0.bindings["dismiss"] = ["x"] }, "retry after invalid Settings edit works")
    let stale = store.resolved.configuration
    config = stale
    config.globalHotkey = "alt+space"
    try JSONEncoder().encode(config).write(to: url, options: .atomic)
    try check(!store.edit(expected: stale) { $0.bindings["pin"] = [] }, "stale Settings editor cannot overwrite external changes")
    try check(store.resolved.globalHotkey?.text == "alt+space", "Settings re-reads pending external changes")
    try check(store.edit { $0.globalHotkey = nil }, "disable global")
    let restarted = KeybindingStore(url: url, watch: false)
    try check(restarted.resolved.globalHotkey == nil, "global stays disabled after restart")
    try Data("not json".utf8).write(to: url, options: .atomic)
    store.reset()
    try check(store.resolved.configuration == KeybindingConfiguration(), "reset restores defaults")
    try check(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.contains("recovery-") }, "reset preserves broken config")
    let migrated = KeybindingStore(url: directory.appendingPathComponent("migrated.json"), legacyShortcut: .optionSpace, watch: false)
    try check(migrated.resolved.globalHotkey?.text == "alt+space", "legacy hotkey migrates once")
    let unmigrated = KeybindingStore(url: migrated.url, legacyShortcut: .optionG, watch: false)
    try check(unmigrated.resolved.globalHotkey?.text == "alt+space", "existing file takes priority over legacy preference")
    let unwritable = KeybindingStore(url: directory.appendingPathComponent("keybindings.json/child.json"), watch: false)
    try check(unwritable.errorMessage != nil, "write error is visible")

    var status = OSStatus(eventHotKeyExistsErr)
    var registrations: [(UInt32, UInt32)] = []
    let hotkeys = GlobalShortcutController(keys: store, action: {}, registerHotKey: { key, modifiers, _ in
      registrations.append((key, modifiers)); return status
    })
    try withExtendedLifetime(hotkeys) {
      try check(registrations.first?.0 == UInt32(kVK_Space), "global default uses Space")
      try check(registrations.first?.1 == UInt32(controlKey | shiftKey), "global default uses Control and Shift")
      try check(store.registrationError != nil, "registration failure is visible")
      status = noErr
      store.isRecording = true
      try check(store.registrationError == nil, "recording suspends global hotkey")
      store.isRecording = false
      try check(registrations.count == 2 && store.registrationError == nil, "recording completion restores global hotkey")
    }
    let watchedURL = directory.appendingPathComponent("watched.json")
    let watched = KeybindingStore(url: watchedURL)
    var external = KeybindingConfiguration()
    external.bindings["dismiss"] = ["x"]
    try JSONEncoder().encode(external).write(to: watchedURL, options: .atomic)
    let watchDeadline = Date().addingTimeInterval(3)
    while watched.resolved.configuration != external && Date() < watchDeadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    try check(watched.resolved.configuration == external, "atomic external writes reload through directory watcher")
    print("Passed \(checks) keybinding checks.")
  }
}
