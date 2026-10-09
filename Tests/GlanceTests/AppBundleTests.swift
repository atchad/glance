import XCTest

final class AppBundleTests: XCTestCase {
  func testInfoPlistStartsGlanceAsMenuBarApp() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appending(path: "../../support/Info.plist").standardizedFileURL
    let info = try XCTUnwrap(PropertyListSerialization.propertyList(
      from: Data(contentsOf: url), format: nil) as? [String: Any])
    // Start without a Dock tile; the saved opt-in can promote the app at runtime.
    XCTAssertEqual(info["LSUIElement"] as? Bool, true)
    XCTAssertNil(info["LSBackgroundOnly"])
  }
}
