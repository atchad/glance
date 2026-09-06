import AppKit
import XCTest
@testable import Glance

final class PullRequestDetailsTests: XCTestCase {
  func testCopyPreservesFullTitleExactly() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let title = "  Fix **literal markdown** & Unicode 🐙\n" + String(repeating: "Long title — ", count: 100)
    PullRequestDetailsView.copyTitle(title, to: pasteboard)
    XCTAssertEqual(pasteboard.string(forType: .string), title)
  }

  func testStatesRemainDistinctIncludingUnknownAndNeutral() {
    let states: [PullRequest.CheckState] = [.success, .failure, .pending, .neutral, .unknown]
    XCTAssertEqual(states.map(\.detailLabel), ["Passed", "Failed", "Pending", "Neutral", "Unknown"])
    XCTAssertEqual(Set(states.map(\.detailSymbol)).count, states.count)
  }

  @MainActor
  func testNativeTriggerActivatesAndNavigatesWithUnmodifiedKeys() {
    let trigger = DetailActionButton.Trigger()
    var activations = 0
    var movements: [Int] = []
    trigger.performAction = { activations += 1 }
    trigger.navigate = { movements.append($0) }
    for code: UInt16 in [36, 76, 49] {
      trigger.keyDown(with: keyEvent(code: code))
    }
    for (code, characters): (UInt16, String) in [(125, ""), (126, ""), (38, "j"), (40, "k")] {
      trigger.keyDown(with: keyEvent(code: code, characters: characters))
    }
    XCTAssertEqual(activations, 3)
    XCTAssertEqual(movements, [1, -1, 1, -1])
    XCTAssertTrue(trigger.acceptsFirstResponder)
    XCTAssertFalse(trigger.handleDetailKey(keyEvent(code: 0, characters: "a")))
  }

  @MainActor
  func testNativeCopyActionReplacesPasteboardOnReturnAndSpace() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let button = DetailActionButton.Trigger()
    let title = "Full literal title 🐙 **exact**"
    button.performAction = { PullRequestDetailsView.copyTitle(title, to: pasteboard) }
    for code: UInt16 in [36, 49] {
      pasteboard.clearContents()
      pasteboard.setString("sentinel", forType: .string)
      button.keyDown(with: keyEvent(code: code))
      XCTAssertEqual(pasteboard.string(forType: .string), title)
    }
  }

  @MainActor
  func testNativeTriggerLeavesModifiedKeysForNormalAppKitRouting() {
    let trigger = DetailActionButton.Trigger()
    trigger.performAction = { XCTFail("Modified key must not activate details") }
    trigger.navigate = { _ in XCTFail("Modified key must not navigate rows") }
    for modifiers: NSEvent.ModifierFlags in [.command, .control, .option, .shift, [.command, .shift]] {
      for (code, characters): (UInt16, String) in [
        (36, "\r"), (76, "\r"), (49, " "), (125, ""), (126, ""), (38, "j"), (40, "k")
      ] {
        XCTAssertFalse(trigger.handleDetailKey(keyEvent(code: code, characters: characters, modifiers: modifiers)))
      }
    }
  }

  private func keyEvent(
    code: UInt16, characters: String = "", modifiers: NSEvent.ModifierFlags = []
  ) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
      windowNumber: 0, context: nil, characters: characters,
      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
  }

}
