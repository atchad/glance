import Carbon
import Combine
import Foundation

@MainActor
final class GlobalShortcutController: ObservableObject {
  private var hotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private var cancellable: AnyCancellable?
  private let action: () -> Void
  private weak var store: AppStore?
  private var handlerStatus: OSStatus = noErr
  private let registerHotKey: (UInt32, UInt32, UnsafeMutablePointer<EventHotKeyRef?>) -> OSStatus

  init(
    store: AppStore, action: @escaping () -> Void,
    registerHotKey: @escaping (UInt32, UInt32, UnsafeMutablePointer<EventHotKeyRef?>) -> OSStatus = {
      key, modifiers, reference in
      RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: OSType(0x474C4E43), id: 1),
        GetApplicationEventTarget(), 0, reference)
    }
  ) {
    self.action = action
    self.store = store
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

    cancellable = store.$preferences
      .map(\.globalShortcut)
      .removeDuplicates()
      .sink { [weak self] shortcut in self?.register(shortcut) }
  }

  deinit {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let eventHandler { RemoveEventHandler(eventHandler) }
  }

  private func register(_ shortcut: GlobalShortcut) {
    if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
    let configuration: (UInt32, UInt32)? = switch shortcut {
    case .none: nil
    case .optionSpace: (UInt32(kVK_Space), UInt32(optionKey))
    case .controlSpace: (UInt32(kVK_Space), UInt32(controlKey))
    case .optionG: (UInt32(kVK_ANSI_G), UInt32(optionKey))
    }
    guard let configuration else {
      store?.shortcutErrorMessage = nil
      return
    }
    let status = handlerStatus == noErr
      ? registerHotKey(configuration.0, configuration.1, &hotKey) : handlerStatus
    store?.shortcutErrorMessage = status == noErr ? nil
      : "Couldn’t enable this shortcut. Choose another shortcut or turn it off."
  }
}
