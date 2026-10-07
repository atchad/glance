import Carbon
import Combine
import Foundation

@MainActor
final class GlobalShortcutController: ObservableObject {
  private var hotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private var cancellable: AnyCancellable?
  private var inputSourceObserver: NSObjectProtocol?
  private let action: () -> Void
  private weak var keys: KeybindingStore?
  private var handlerStatus: OSStatus = noErr
  private let registerHotKey: (UInt32, UInt32, UnsafeMutablePointer<EventHotKeyRef?>) -> OSStatus

  init(
    keys: KeybindingStore, action: @escaping () -> Void,
    registerHotKey: @escaping (UInt32, UInt32, UnsafeMutablePointer<EventHotKeyRef?>) -> OSStatus = {
      key, modifiers, reference in
      RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: OSType(0x474C4E43), id: 1),
        GetApplicationEventTarget(), 0, reference)
    }
  ) {
    self.action = action
    self.keys = keys
    self.registerHotKey = registerHotKey
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userData in
        guard let userData else { return noErr }
        let controller = Unmanaged<GlobalShortcutController>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in controller.action() }
        return noErr
      }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

    cancellable = keys.$resolved
      .combineLatest(keys.$isRecording)
      .map { resolved, recording in recording ? nil : resolved.globalHotkey }
      .removeDuplicates()
      .sink { [weak self] shortcut in self?.register(shortcut) }
    inputSourceObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, let keys = self.keys else { return }
        self.register(keys.isRecording ? nil : keys.resolved.globalHotkey)
      }
    }
  }

  deinit {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let eventHandler { RemoveEventHandler(eventHandler) }
    if let inputSourceObserver { DistributedNotificationCenter.default().removeObserver(inputSourceObserver) }
  }

  private func register(_ shortcut: KeyChord?) {
    if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
    guard let shortcut else {
      keys?.registrationError = nil
      return
    }
    guard let key = shortcut.carbonKeyCode else {
      keys?.registrationError = "This global key is not available in the current keyboard layout. Choose another key."
      return
    }
    let status = handlerStatus == noErr
      ? registerHotKey(key, shortcut.carbonModifiers, &hotKey) : handlerStatus
    keys?.registrationError = status == noErr ? nil
      : "Could not enable the global hotkey. It may be in use by another app. Choose another hotkey or turn it off."
  }
}
