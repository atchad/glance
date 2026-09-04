import Carbon
import Combine
import Foundation

@MainActor
final class GlobalShortcutController: ObservableObject {
  private var hotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private var cancellable: AnyCancellable?
  private let action: () -> Void

  init(store: AppStore, action: @escaping () -> Void) {
    self.action = action
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
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
    guard let configuration else { return }
    let identifier = EventHotKeyID(signature: OSType(0x474C4E43), id: 1)
    RegisterEventHotKey(
      configuration.0, configuration.1, identifier, GetApplicationEventTarget(), 0, &hotKey)
  }
}
