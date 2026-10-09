import XCTest

final class AppBundleTests: XCTestCase {
  func testInfoPlistKeepsGlanceInDockAndAppSwitcher() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appending(path: "../../support/Info.plist").standardizedFileURL
    let info = try XCTUnwrap(PropertyListSerialization.propertyList(
      from: Data(contentsOf: url), format: nil) as? [String: Any])
    // Agent and background-only apps have no Dock tile and are skipped by Command-Tab.
    XCTAssertNil(info["LSUIElement"])
    XCTAssertNil(info["LSBackgroundOnly"])
  }
}
