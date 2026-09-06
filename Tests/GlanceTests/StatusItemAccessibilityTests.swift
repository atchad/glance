import XCTest
@testable import Glance

final class StatusItemAccessibilityTests: XCTestCase {
  @MainActor
  func testCountAndFreshnessDescribeCurrentState() {
    XCTAssertEqual(StatusItemController.accessibilityValue(
      count: 3, mode: .awaitingReview, isRefreshing: true, lastUpdated: nil,
      connectionIssue: .unavailable), "3 — Awaiting my review. Refreshing")
    XCTAssertEqual(StatusItemController.accessibilityValue(
      count: nil, mode: .none, isRefreshing: false, lastUpdated: nil,
      connectionIssue: nil), "Count hidden. Not refreshed yet")
    XCTAssertTrue(StatusItemController.accessibilityValue(
      count: 3, mode: .allShown, isRefreshing: false, lastUpdated: Date(),
      connectionIssue: .authentication).hasSuffix("Refresh unavailable; showing saved results"))
    XCTAssertTrue(StatusItemController.accessibilityValue(
      count: nil, mode: .none, isRefreshing: false, lastUpdated: nil,
      connectionIssue: .unavailable).hasSuffix("Refresh unavailable; no results loaded"))
    XCTAssertTrue(StatusItemController.accessibilityValue(
      count: 3, mode: .allShown, isRefreshing: false, lastUpdated: Date(),
      connectionIssue: nil).contains("Last updated"))
  }
}
