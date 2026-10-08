import AppKit
import XCTest
@testable import Glance

@MainActor
final class DockIconTests: XCTestCase {
  func testNewAndOlderProfilesShowDockIconByDefault() throws {
    XCTAssertTrue(Preferences().showDockIcon)
    for json in ["{}", "{\"showDockIcon\":null}", "{\"showAuthor\":false}"] {
      let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
      XCTAssertTrue(preferences.showDockIcon)
      XCTAssertFalse(preferences.recoveredInvalidValues)
    }
  }

  func testDockIconVisibilityRoundTripsBothChoices() throws {
    for visible in [false, true] {
      var preferences = Preferences()
      preferences.showDockIcon = visible
      preferences.showAuthor = false
      let saved = try JSONEncoder().encode(preferences)
      let reloaded = try JSONDecoder().decode(Preferences.self, from: saved)
      XCTAssertEqual(reloaded.showDockIcon, visible)
      XCTAssertFalse(reloaded.showAuthor)
    }
  }

  func testStartupAppliesSavedHiddenPreference() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    store.preferences.showDockIcon = false
    let reloaded = AppStore(storageDirectory: directory)
    XCTAssertFalse(reloaded.preferences.showDockIcon)

    let applied = expectation(description: "Apply saved Dock visibility at startup")
    let delegate = GlanceAppDelegate()
    var policies: [NSApplication.ActivationPolicy] = []
    // Record the platform call without changing the test process's Dock icon or focus.
    delegate.configureDockIcon(store: reloaded, applyPolicy: {
      policies.append($0)
      applied.fulfill()
    })
    await fulfillment(of: [applied], timeout: 2)
    withExtendedLifetime(delegate) {
      XCTAssertEqual(policies, [.accessory])
    }
  }

  func testLiveChangesApplyOnlyWhenDockVisibilityChanges() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    let applied = expectation(description: "Apply initial visibility and both toggle directions")
    applied.expectedFulfillmentCount = 3
    applied.assertForOverFulfill = true
    let delegate = GlanceAppDelegate()
    var policies: [NSApplication.ActivationPolicy] = []
    delegate.configureDockIcon(store: store, applyPolicy: {
      policies.append($0)
      applied.fulfill()
    })
    store.preferences.showAuthor = false
    store.preferences.showDockIcon = false
    store.preferences.showDockIcon = false
    store.preferences.refreshInterval = 30
    store.preferences.showDockIcon = true
    await fulfillment(of: [applied], timeout: 2)
    withExtendedLifetime(delegate) {
      XCTAssertEqual(policies, [.regular, .accessory, .regular])
    }
    let reloaded = AppStore(storageDirectory: directory)
    XCTAssertTrue(reloaded.preferences.showDockIcon)
    XCTAssertFalse(reloaded.preferences.showAuthor)
    XCTAssertEqual(reloaded.preferences.refreshInterval, 30)
  }
}
