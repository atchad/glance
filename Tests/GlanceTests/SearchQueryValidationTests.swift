import XCTest

@testable import Glance

final class SearchQueryValidationTests: XCTestCase {
  func testEditingInvalidatesAnInflightValidationEvenWhenTextIsRestored() {
    var validation = SearchQueryValidation()
    let oldRequest = validation.begin()
    validation.reset()
    XCTAssertFalse(validation.finish(oldRequest, error: nil))
    XCTAssertEqual(validation.state, .idle)

    let currentRequest = validation.begin()
    XCTAssertFalse(validation.finish(oldRequest, error: "Old error"))
    XCTAssertEqual(validation.state, .validating)
    XCTAssertTrue(validation.finish(currentRequest, error: nil))
    XCTAssertEqual(validation.state, .valid)
  }

  func testRejectedQueryCannotBecomeValid() {
    var validation = SearchQueryValidation()
    let request = validation.begin()
    XCTAssertFalse(validation.finish(request, error: "Missing pull request filter"))
    XCTAssertEqual(validation.state, .invalid("Missing pull request filter"))
  }

  @MainActor
  func testValidatedEditTargetsIdentityAfterMoveAndIgnoresDeletion() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory) { _ in ("", []) }
    let original = store.preferences.sections[0]
    store.preferences.sections.reverse()
    store.updateSectionQuery(id: original.id, query: "is:pr author:@me")
    XCTAssertEqual(store.preferences.sections.first { $0.id == original.id }?.query,
      "is:pr author:@me")
    store.preferences.sections.removeAll { $0.id == original.id }
    let remaining = store.preferences.sections.map(\.query)
    store.updateSectionQuery(id: original.id, query: "is:pr is:closed")
    XCTAssertEqual(store.preferences.sections.map(\.query), remaining)
  }
}
