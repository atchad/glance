import Foundation
import XCTest

@testable import Glance

@MainActor
final class StorageRecoveryTests: XCTestCase {
  func testMissingFilesAreNormalFirstLaunch() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    XCTAssertNil(store.storageErrorMessage)
    store.preferences.showAuthor = false
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appending(path: "preferences.json").path))
    XCTAssertNil(store.storageErrorMessage)
  }

  func testCorruptFilesArePreservedBeforeReplacement() async throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let damaged = Data("not JSON".utf8)
    for name in ["preferences.json", "cache.json"] {
      try damaged.write(to: directory.appending(path: name))
    }
    let store = AppStore(storageDirectory: directory) { _ in ("viewer", []) }
    XCTAssertNotNil(store.storageErrorMessage)
    for name in ["preferences.json", "cache.json"] {
      let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil).first {
          $0.lastPathComponent.hasPrefix(name + ".recovery-")
        })
      XCTAssertEqual(try Data(contentsOf: backup), damaged)
      XCTAssertEqual(try Data(contentsOf: directory.appending(path: name)), damaged)
    }
    store.preferences.showAuthor = false
    store.refresh()
    await waitForRefresh(store)
    XCTAssertNotEqual(try Data(contentsOf: directory.appending(path: "cache.json")), damaged)
    XCTAssertNotNil(store.storageErrorMessage)
  }

  func testFailedPreservationLeavesOriginalUntouched() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try? FileManager.default.removeItem(at: directory)
    }
    let file = directory.appending(path: "preferences.json")
    let damaged = Data("not JSON".utf8)
    try damaged.write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    let store = AppStore(storageDirectory: directory)
    XCTAssertTrue(store.storageErrorMessage?.contains("Saving this file is disabled") == true)
    // Even if the directory becomes writable, this session must not overwrite unpreserved data.
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    store.preferences.showAuthor = false
    XCTAssertEqual(try Data(contentsOf: file), damaged)
  }

  func testUnreadablePreferencesAreReportedWithoutOverwriting() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appending(path: "preferences.json")
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      try? FileManager.default.removeItem(at: directory)
    }
    let original = Data("{\"showAuthor\":false}".utf8)
    try original.write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    let store = AppStore(storageDirectory: directory)
    XCTAssertNotNil(store.storageErrorMessage)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    XCTAssertEqual(try Data(contentsOf: file), original)
  }

  func testWriteFailureIsVisibleAndClearsAfterSuccessfulSave() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    let file = directory.appending(path: "preferences.json")
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
    store.preferences.showAuthor = false
    XCTAssertTrue(store.storageErrorMessage?.contains("Couldn’t save preferences.json") == true)
    try FileManager.default.removeItem(at: file)
    store.preferences.showAuthor = true
    XCTAssertNil(store.storageErrorMessage)
  }

  func testDuplicateIDsKeepFirstEntryAndValidPreferences() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var preferences = Preferences.default
    let first = preferences.sections[0]
    var duplicate = first
    duplicate.name = "Duplicate"
    preferences.sections = [first, duplicate]
    preferences.showAuthor = false
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(preferences).write(to: directory.appending(path: "preferences.json"))
    let cache = GlanceCache(savedAt: .now, viewerLogin: "viewer", snapshots: [
      SectionSnapshot(id: first.id, pullRequests: []),
      SectionSnapshot(id: first.id, pullRequests: []),
    ])
    try encoder.encode(cache).write(to: directory.appending(path: "cache.json"))
    let originals = try ["preferences.json", "cache.json"].map {
      try Data(contentsOf: directory.appending(path: $0))
    }
    let store = AppStore(storageDirectory: directory)
    XCTAssertNotNil(store.storageErrorMessage)
    for (index, name) in ["preferences.json", "cache.json"].enumerated() {
      try assertBackup(originals[index], named: name, in: directory)
    }
    XCTAssertEqual(store.preferences.sections.map(\.name), [first.name])
    XCTAssertFalse(store.preferences.showAuthor)
    XCTAssertEqual(store.snapshots.count, 1)
    XCTAssertEqual(store.menuBarCount, 0)
  }

  func testNormalizedIntervalPreservesOriginalBeforeSaving() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = Data("{\"refreshInterval\":-1,\"showAuthor\":false}".utf8)
    let file = directory.appending(path: "preferences.json")
    try original.write(to: file)
    let store = AppStore(storageDirectory: directory)
    XCTAssertEqual(store.preferences.refreshInterval, 60)
    XCTAssertFalse(store.preferences.showAuthor)
    XCTAssertNotNil(store.storageErrorMessage)
    store.preferences.showUpdatedAt = false
    try assertBackup(original, named: "preferences.json", in: directory)
    XCTAssertNotEqual(try Data(contentsOf: file), original)
  }

  private func assertBackup(_ original: Data, named name: String, in directory: URL) throws {
    let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil).first {
        $0.lastPathComponent.hasPrefix(name + ".recovery-")
      })
    XCTAssertEqual(try Data(contentsOf: backup), original)
  }

  func testInvalidRefreshIntervalsUseDefaultAndKeepOtherFields() throws {
    for value in ["0", "-1", "14", "901", "1e999", "\"NaN\""] {
      let preferences = try JSONDecoder().decode(Preferences.self, from: Data(
        "{\"refreshInterval\":\(value),\"showAuthor\":false}".utf8))
      XCTAssertEqual(preferences.refreshInterval, 60)
      XCTAssertFalse(preferences.showAuthor)
    }
    for value in [Double.nan, .infinity, -.infinity, 0, 901] {
      var preferences = Preferences.default
      preferences.refreshInterval = value
      XCTAssertEqual(preferences.refreshInterval, 60)
    }
    for value in [15.0, 60, 900] {
      var preferences = Preferences.default
      preferences.refreshInterval = value
      XCTAssertEqual(preferences.refreshInterval, value)
    }
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  }

  private func waitForRefresh(_ store: AppStore) async {
    for _ in 0..<1000 {
      if !store.isRefreshing { return }
      try? await Task.sleep(for: .milliseconds(1))
    }
    XCTFail("Refresh did not finish")
  }
}
