import XCTest

@testable import Glance

final class SectionQueryDraftTests: XCTestCase {
  func testExamplesRejectOldValidationIncludingSameQueryAndRoundTrip() throws {
    var draft = SectionQueryDraft()
    draft.apply(.assignedToMe)
    let oldRequest = try XCTUnwrap(draft.beginValidation())
    draft.apply(.assignedToMe)
    XCTAssertFalse(draft.validation.finish(oldRequest, error: nil))
    XCTAssertFalse(draft.canAdd)

    let secondRequest = try XCTUnwrap(draft.beginValidation())
    draft.apply(.myNonDraftPRs)
    draft.apply(.assignedToMe)
    XCTAssertFalse(draft.validation.finish(secondRequest, error: nil))
    XCTAssertEqual(draft.validation.state, .idle)
  }

  func testRepositoryTemplateRequiresReplacementBeforeValidationAndAdd() throws {
    var draft = SectionQueryDraft()
    draft.apply(.repositoryPRs)
    XCTAssertTrue(draft.requiresRepositoryReplacement)
    XCTAssertNil(draft.beginValidation())
    XCTAssertFalse(draft.canAdd)
    draft.query = "is:pr is:open repo:apple/swift"
    XCTAssertFalse(draft.requiresRepositoryReplacement)
    let request = try XCTUnwrap(draft.beginValidation())
    XCTAssertTrue(draft.validation.finish(request, error: nil))
    XCTAssertTrue(draft.canAdd)
    draft.query += " draft:false"
    XCTAssertFalse(draft.canAdd)
  }

  func testExamplesClearSuccessfulValidation() throws {
    var draft = SectionQueryDraft()
    for example in SectionQueryExample.allCases {
      draft.apply(.assignedToMe)
      let request = try XCTUnwrap(draft.beginValidation())
      XCTAssertTrue(draft.validation.finish(request, error: nil))
      XCTAssertTrue(draft.canAdd)
      draft.apply(example)
      XCTAssertEqual(draft.name, example.name)
      XCTAssertEqual(draft.query, example.query)
      XCTAssertEqual(draft.validation.state, .idle)
      XCTAssertFalse(draft.canAdd)
    }
  }
}
