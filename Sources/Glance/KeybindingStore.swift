import AppKit
import Combine

@MainActor
final class KeybindingStore: ObservableObject {
  nonisolated static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Glance/keybindings.json")
  }

  @Published private(set) var resolved: ResolvedKeybindings
  @Published private(set) var errorMessage: String?
  @Published var registrationError: String?
  @Published var isRecording = false
  let url: URL
  private var observedData: Data?
  private var fileIsValid = true
  private var watcher: DispatchSourceFileSystemObject?

  init(url: URL = KeybindingStore.defaultURL, legacyShortcut: GlobalShortcut = .none, watch: Bool = true) {
    self.url = url
    var configuration = KeybindingConfiguration()
    switch legacyShortcut {
    case .none: break
    case .optionSpace: configuration.globalHotkey = "alt+space"
    case .controlSpace: configuration.globalHotkey = "ctrl+space"
    case .optionG: configuration.globalHotkey = "alt+g"
    }
    // Built-in defaults are validated by the same interface as file and Settings edits.
    resolved = try! ResolvedKeybindings(configuration)
    if FileManager.default.fileExists(atPath: url.path) {
      reload()
    } else {
      _ = save(configuration)
    }
    if watch { startWatching() }
  }

  deinit { watcher?.cancel() }

  func reload() {
    do {
      let data = try Data(contentsOf: url)
      guard data != observedData || !fileIsValid else { return }
      observedData = data
      guard data.count <= 65_536 else { throw KeybindingError(message: "The keybindings file must be at most 64 KB.") }
      let configuration = try JSONDecoder().decode(KeybindingConfiguration.self, from: data)
      let next = try ResolvedKeybindings(configuration)
      resolved = next
      fileIsValid = true
      errorMessage = nil
    } catch {
      fileIsValid = false
      errorMessage = "Keybindings: \(error.localizedDescription) The last valid bindings remain active."
    }
  }

  /// Re-read before editing to avoid overwriting an external edit that the watcher has not seen yet.
  @discardableResult
  func edit(expected: KeybindingConfiguration? = nil, _ update: (inout KeybindingConfiguration) -> Void) -> Bool {
    reload()
    guard fileIsValid else { return false }
    if let expected, expected != resolved.configuration {
      errorMessage = "The config file changed while this editor was open. Close the editor and try again."
      return false
    }
    var configuration = resolved.configuration
    update(&configuration)
    return save(configuration)
  }

  @discardableResult
  func save(_ configuration: KeybindingConfiguration) -> Bool {
    do {
      let next = try ResolvedKeybindings(configuration)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(configuration)
      guard data.count <= 65_536 else { throw KeybindingError(message: "The keybindings file must be at most 64 KB.") }
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      observedData = data
      resolved = next
      fileIsValid = true
      errorMessage = nil
      return true
    } catch {
      errorMessage = "Could not save keybindings: \(error.localizedDescription)"
      return false
    }
  }

  func reset() {
    reload()
    if !fileIsValid, FileManager.default.fileExists(atPath: url.path) {
      do {
        let data = try Data(contentsOf: url)
        try data.write(to: url.deletingPathExtension().appendingPathExtension("recovery-\(UUID().uuidString).json"))
      } catch {
        errorMessage = "Could not preserve the invalid file. Reset was cancelled."
        return
      }
    }
    _ = save(KeybindingConfiguration())
  }
  func revealFile() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
  func label(for action: GlanceAction) -> String {
    resolved.sequences(for: action).map(\.display).joined(separator: ", ")
  }
  func help(for action: GlanceAction) -> String {
    let label = label(for: action)
    return action.title + (label.isEmpty ? "" : " (\(label))")
  }

  private func startWatching() {
    // Watch the directory: editors and our atomic writes replace the file's inode.
    let fd = open(url.deletingLastPathComponent().path, O_EVTONLY)
    guard fd >= 0 else {
      errorMessage = "Could not watch the keybindings folder. Reopen Glance after external edits."
      return
    }
    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
    source.setEventHandler { [weak self] in self?.reload() }
    source.setCancelHandler { close(fd) }
    watcher = source
    source.resume()
  }
}
