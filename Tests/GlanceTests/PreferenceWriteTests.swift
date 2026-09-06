import XCTest
@testable import Glance

@MainActor
final class PreferenceWriteTests: XCTestCase {
  func testSameValueRetriesAfterStorageRecovers() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    store.preferences.showAuthor = false
    let file = directory.appending(path: "preferences.json")
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    store.preferences.showAuthor = true
    XCTAssertNotNil(store.storageIssues["preferences.json-save"])
    try FileManager.default.removeItem(at: file)
    store.preferences.showAuthor = true
    XCTAssertNil(store.storageIssues["preferences.json-save"])
    XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: file)).showAuthor)
  }

  func testUnchangedPreferencesSkipWriteAndChangedValuesPersistImmediately() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    store.preferences.showAuthor = false
    let file = directory.appending(path: "preferences.json")
    let previous = Date(timeIntervalSince1970: 1000)
    try FileManager.default.setAttributes([.modificationDate: previous], ofItemAtPath: file.path)
    store.preferences.showAuthor = false
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    XCTAssertEqual(attributes[.modificationDate] as? Date, previous)
    store.preferences.showAuthor = true
    let saved = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: file))
    XCTAssertTrue(saved.showAuthor)
  }
}
