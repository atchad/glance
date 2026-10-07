import AppKit
import Carbon
import SwiftUI

extension KeyChord {
  init?(event: NSEvent) {
    let named: [UInt16: String] = [49: "space", 36: "return", 76: "return", 53: "escape", 48: "tab",
      123: "left", 124: "right", 125: "down", 126: "up", 115: "home", 119: "end",
      116: "pageup", 121: "pagedown", 51: "delete", 117: "forwarddelete"]
    guard let key = named[event.keyCode] ?? Self.functionKeys[event.keyCode]
      ?? event.characters(byApplyingModifiers: [])?.lowercased() else { return nil }
    var parts: [String] = []
    if event.modifierFlags.contains(.control) { parts.append("ctrl") }
    if event.modifierFlags.contains(.option) { parts.append("alt") }
    if event.modifierFlags.contains(.shift) { parts.append("shift") }
    if event.modifierFlags.contains(.command) { parts.append("cmd") }
    parts.append(key)
    guard let chord = try? KeyChord(parts.joined(separator: "+")) else { return nil }
    self = chord
  }

  var eventModifiers: NSEvent.ModifierFlags {
    var result: NSEvent.ModifierFlags = []
    if modifiers.contains(.ctrl) { result.insert(.control) }
    if modifiers.contains(.alt) { result.insert(.option) }
    if modifiers.contains(.shift) { result.insert(.shift) }
    if modifiers.contains(.cmd) { result.insert(.command) }
    return result
  }

  var swiftUIModifiers: SwiftUI.EventModifiers {
    var result: SwiftUI.EventModifiers = []
    if modifiers.contains(.ctrl) { result.insert(.control) }
    if modifiers.contains(.alt) { result.insert(.option) }
    if modifiers.contains(.shift) { result.insert(.shift) }
    if modifiers.contains(.cmd) { result.insert(.command) }
    return result
  }

  var keyEquivalent: String {
    let equivalents = ["space": " ", "return": "\r", "escape": "\u{1b}",
      "up": "\u{f700}", "down": "\u{f701}", "left": "\u{f702}", "right": "\u{f703}",
      "home": "\u{f729}", "end": "\u{f72b}", "pageup": "\u{f72c}", "pagedown": "\u{f72d}",
      "delete": "\u{7f}", "forwarddelete": "\u{f728}"]
    if let functionKey = Self.functionKeys.first(where: { $0.value == key }),
      let number = Int(functionKey.value.dropFirst()), let scalar = UnicodeScalar(0xf703 + number) {
      return String(scalar)
    }
    return equivalents[key] ?? key
  }

  var carbonModifiers: UInt32 {
    var result: UInt32 = 0
    if modifiers.contains(.ctrl) { result |= UInt32(controlKey) }
    if modifiers.contains(.alt) { result |= UInt32(optionKey) }
    if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
    if modifiers.contains(.cmd) { result |= UInt32(cmdKey) }
    return result
  }

  var carbonKeyCode: UInt32? {
    let named: [String: UInt32] = ["space": 49, "return": 36, "up": 126, "down": 125, "left": 123,
      "right": 124, "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "delete": 51, "forwarddelete": 117]
    if let code = named[key] { return code }
    if let code = Self.functionKeys.first(where: { $0.value == key })?.key { return UInt32(code) }
    // Translate physical keys with no modifiers in the active layout, not a fixed US letter map.
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
    guard let bytes = CFDataGetBytePtr(data) else { return nil }
    let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    for code in UInt16(0)...UInt16(127) {
      var deadKey: UInt32 = 0
      var count = 0
      var characters = [UniChar](repeating: 0, count: 4)
      let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKey, characters.count, &count, &characters)
      if status == noErr, String(utf16CodeUnits: characters, count: count).lowercased() == key { return UInt32(code) }
    }
    return nil
  }

  private static let functionKeys: [UInt16: String] = [122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5",
    97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12", 105: "f13",
    107: "f14", 113: "f15", 106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20"]
}

extension KeybindingStore {
  // Only command-modified, one-chord bindings belong in the macOS application menu.
  // Other bindings remain scoped to the dashboard and must not capture Settings text fields.
  func menuChord(for action: GlanceAction) -> KeyChord? {
    resolved.sequences(for: action).first { $0.chords.count == 1 && $0.chords[0].modifiers.contains(.cmd) }?.chords.first
  }
}

struct CommandButton: View {
  @ObservedObject var keys: KeybindingStore
  let action: GlanceAction
  let perform: () -> Void
  var enabled = true

  var body: some View {
    if let chord = keys.menuChord(for: action) {
      button.keyboardShortcut(KeyEquivalent(Character(chord.keyEquivalent)), modifiers: chord.swiftUIModifiers)
    } else {
      button
    }
  }

  private var button: some View {
    Button(action.title + (action == .settings || action == .checkForUpdates ? "…" : ""), action: perform).disabled(!enabled)
  }
}

/// A window-scoped adapter. Child popovers, menus, editors, and native controls keep their keys.
struct DashboardKeyboardInput: NSViewRepresentable {
  let handle: (KeyChord, Bool, Bool, Bool) -> Bool
  let cancel: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.view = view
    context.coordinator.install()
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {
    context.coordinator.handle = handle
    context.coordinator.cancel = cancel
  }
  func makeCoordinator() -> Coordinator { Coordinator(handle: handle, cancel: cancel) }
  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }

  final class Coordinator {
    weak var view: NSView?
    var handle: (KeyChord, Bool, Bool, Bool) -> Bool
    var cancel: () -> Void
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var menuTracking = false

    init(handle: @escaping (KeyChord, Bool, Bool, Bool) -> Bool, cancel: @escaping () -> Void) {
      self.handle = handle
      self.cancel = cancel
    }
    func install() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
        guard let self else { return event }
        guard event.type == .keyDown else { self.cancel(); return event }
        guard let window = self.view?.window, event.window === window, window.isKeyWindow,
          window.attachedSheet == nil, !self.menuTracking, let chord = KeyChord(event: event) else {
          self.cancel()
          return event
        }
        let responder = window.firstResponder
        if responder is DetailActionButton.Trigger, chord.modifiers.isEmpty,
          ["return", "space"].contains(chord.key) { self.cancel(); return event }
        let textEditing = responder is NSTextView || (responder as? NSTextField)?.isEditable == true
        // Button activation and arrows are native. Printable bindings (including custom navigation)
        // still work on the explicit details trigger.
        let nativeControl = responder is NSControl && !(responder is DetailActionButton.Trigger)
        return self.handle(chord, textEditing, nativeControl, event.isARepeat) ? nil : event
      }
      let center = NotificationCenter.default
      for name in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.cancel() })
      }
      observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
        self?.menuTracking = true
        self?.cancel()
      })
      observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in self?.menuTracking = false })
    }
    func remove() {
      if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
      observers.forEach(NotificationCenter.default.removeObserver)
      observers = []
      cancel()
    }
    deinit {
      if let monitor { NSEvent.removeMonitor(monitor) }
      observers.forEach(NotificationCenter.default.removeObserver)
    }
  }
}
