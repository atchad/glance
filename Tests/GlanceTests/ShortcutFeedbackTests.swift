import Carbon
import XCTest
@testable import Glance

@MainActor
final class ShortcutFeedbackTests: XCTestCase {
  func testRegistrationFailureRecoveryAndRecorderFollowConfigChanges() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keys = KeybindingStore(url: directory.appendingPathComponent("keybindings.json"), watch: false)
    keys.edit { $0.globalHotkey = nil }
    var status = OSStatus(eventHotKeyExistsErr)
    var attempts = 0
    let controller = GlobalShortcutController(keys: keys, action: {}, registerHotKey: { _, _, _ in
      attempts += 1
      return status
    })
    withExtendedLifetime(controller) {
      XCTAssertNil(keys.registrationError)
      keys.edit { $0.globalHotkey = "alt+g" }
      XCTAssertEqual(attempts, 1)
      XCTAssertNotNil(keys.registrationError)
      status = noErr
      keys.edit { $0.globalHotkey = "alt+space" }
      XCTAssertEqual(attempts, 2)
      XCTAssertNil(keys.registrationError)
      status = OSStatus(eventHotKeyExistsErr)
      keys.edit { $0.globalHotkey = "ctrl+space" }
      XCTAssertNotNil(keys.registrationError)
      keys.isRecording = true
      XCTAssertNil(keys.registrationError)
      XCTAssertEqual(attempts, 3)
      keys.isRecording = false
      XCTAssertEqual(attempts, 4)
      keys.edit { $0.globalHotkey = nil }
      XCTAssertNil(keys.registrationError)
    }
  }
}
