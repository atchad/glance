import Carbon
import XCTest
@testable import Glance

@MainActor
final class ShortcutFeedbackTests: XCTestCase {
  func testRegistrationFailureAndRecoveryFollowPreferenceChanges() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    var status = OSStatus(eventHotKeyExistsErr)
    var attempts = 0
    let controller = GlobalShortcutController(store: store, action: {}, registerHotKey: { _, _, _ in
      attempts += 1
      return status
    })
    withExtendedLifetime(controller) {
      XCTAssertNil(store.shortcutErrorMessage)
      store.preferences.globalShortcut = .optionG
      XCTAssertEqual(attempts, 1)
      XCTAssertNotNil(store.shortcutErrorMessage)
      status = noErr
      store.preferences.globalShortcut = .optionSpace
      XCTAssertEqual(attempts, 2)
      XCTAssertNil(store.shortcutErrorMessage)
      status = OSStatus(eventHotKeyExistsErr)
      store.preferences.globalShortcut = .controlSpace
      XCTAssertNotNil(store.shortcutErrorMessage)
      store.preferences.globalShortcut = .none
      XCTAssertNil(store.shortcutErrorMessage)
      XCTAssertEqual(attempts, 3)
    }
  }
}
