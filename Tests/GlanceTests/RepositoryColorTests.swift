import AppKit
import SwiftUI
import XCTest

@testable import Glance

final class RepositoryColorTests: XCTestCase {
  func testPaletteHasTenDistinctReadableColorsInBothAppearances() throws {
    let presets = RepositoryColor.presets
    XCTAssertEqual(presets.count, 10)
    XCTAssertEqual(Set(presets.map(\.color)).count, 10)
    XCTAssertEqual(Set(presets.map(\.darkHex)).count, 10)
    for preset in presets {
      let light = try XCTUnwrap(NSColor(preset.color.displayColor(for: .light)).usingColorSpace(.sRGB))
      let dark = try XCTUnwrap(NSColor(preset.color.displayColor(for: .dark)).usingColorSpace(.sRGB))
      XCTAssertGreaterThanOrEqual(1.05 / (luminance(light) + 0.05), 4.5, preset.name)
      XCTAssertGreaterThanOrEqual((luminance(dark) + 0.05) / (0.05 + 0.03), 4.5, preset.name)
    }
  }

  func testHexValidationAndColorPickerRoundTrip() throws {
    XCTAssertEqual(RepositoryColor(hex: "12abef")?.hex, "#12ABEF")
    for invalid in ["", "#123", "#12345678", "#xyzxyz", " 123456", "１２３４５６"] {
      XCTAssertNil(RepositoryColor(hex: invalid), invalid)
    }
    for hex in ["#000000", "#FFFFFF", "#12ABEF"] + RepositoryColor.presets.map(\.color.hex) {
      let original = try XCTUnwrap(RepositoryColor(hex: hex))
      XCTAssertEqual(RepositoryColor(color: original.color), original)
    }
    let custom = try XCTUnwrap(RepositoryColor(hex: "#12ABEF"))
    XCTAssertEqual(RepositoryColor(color: custom.displayColor(for: .light)), custom)
    XCTAssertEqual(RepositoryColor(color: custom.displayColor(for: .dark)), custom)
  }

  func testSequentialAssignmentLoopsAndDeduplicatesRepositories() {
    var preferences = Preferences.default
    for index in 0..<23 {
      let repository = "owner/repo-\(index)"
      preferences.assignRepositoryColors(for: [repository, repository.uppercased()])
      XCTAssertEqual(preferences.repositoryColor(for: repository),
        RepositoryColor.presets[index % 10].color)
    }
    XCTAssertEqual(preferences.repositoryColors.count, 23)
  }

  func testBatchOrderIsDeterministicAndOverridesDoNotAdvanceSequence() throws {
    var preferences = Preferences.default
    preferences.assignRepositoryColors(for: ["z/repo", "a/repo", "A/REPO"])
    XCTAssertEqual(preferences.repositoryColor(for: "a/repo"), RepositoryColor.presets[0].color)
    XCTAssertEqual(preferences.repositoryColor(for: "z/repo"), RepositoryColor.presets[1].color)
    let custom = try XCTUnwrap(RepositoryColor(hex: "#12ABEF"))
    preferences.repositoryColors["a/repo"] = custom
    preferences.assignRepositoryColors(for: ["z/repo", "A/REPO", "other/repo"])
    XCTAssertEqual(preferences.repositoryColor(for: "A/REPO"), custom)
    XCTAssertEqual(preferences.repositoryColor(for: "other/repo"), RepositoryColor.presets[2].color)
    XCTAssertEqual(preferences.repositoryColors.count, 3)
  }

  func testOldPreferencesMigrateAndNewColorsRoundTrip() throws {
    var preferences = try JSONDecoder().decode(Preferences.self, from: Data("{\"showAuthor\":false}".utf8))
    XCTAssertTrue(preferences.repositoryColors.isEmpty)
    XCTAssertFalse(preferences.recoveredInvalidValues)
    preferences.assignRepositoryColors(for: ["owner/repo"])
    preferences.repositoryColors["other/repo"] = RepositoryColor(hex: "#12ABEF")
    let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
    XCTAssertEqual(restored, preferences)
  }

  func testInvalidColorsRecoverWithoutLosingOtherPreferencesOrValidColors() throws {
    let json = """
      {"showAuthor":false,"repositoryColors":{"Owner/Repo":"#12abef","bad/repo":"oops"}}
      """
    let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    XCTAssertFalse(preferences.showAuthor)
    XCTAssertTrue(preferences.recoveredInvalidValues)
    XCTAssertEqual(preferences.repositoryColor(for: "owner/repo")?.hex, "#12ABEF")
    XCTAssertEqual(preferences.repositoryColors.count, 1)
    for invalid in ["null", "[]", "42"] {
      let recovered = try JSONDecoder().decode(Preferences.self,
        from: Data("{\"showAuthor\":false,\"repositoryColors\":\(invalid)}".utf8))
      XCTAssertTrue(recovered.recoveredInvalidValues)
      XCTAssertFalse(recovered.showAuthor)
    }
  }

  func testCaseVariantsInStoredColorsCollapseWithoutLosingOtherRepositories() throws {
    let json = """
      {"repositoryColors":{"Owner/Repo":"#12ABEF","owner/repo":"#FFFFFF","other/repo":"#000000"}}
      """
    let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    XCTAssertTrue(preferences.recoveredInvalidValues)
    XCTAssertEqual(preferences.repositoryColors.count, 2)
    XCTAssertEqual(preferences.repositoryColor(for: "OWNER/REPO")?.hex, "#12ABEF")
    XCTAssertEqual(preferences.repositoryColor(for: "other/repo")?.hex, "#000000")
  }

  private func luminance(_ color: NSColor) -> Double {
    let rgb = [color.redComponent, color.greenComponent, color.blueComponent].map { component in
      component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
  }
}

@MainActor
final class RepositoryColorStoreTests: XCTestCase {
  func testAutomaticColorsAndCustomEditsSurviveEmptyResultsExclusionAndRelaunch() async throws {
    let directory = storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    var requests = [pullRequest(repository: "owner/repo"), pullRequest(repository: "other/repo")]
    let store = AppStore(storageDirectory: directory) { sections in
      ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: requests) })
    }
    await refresh(store)
    XCTAssertEqual(store.colorRepositories, ["other/repo", "owner/repo"])
    XCTAssertEqual(store.preferences.repositoryColor(for: "other/repo"), RepositoryColor.presets[0].color)
    XCTAssertEqual(store.preferences.repositoryColor(for: "owner/repo"), RepositoryColor.presets[1].color)
    let custom = try XCTUnwrap(RepositoryColor(hex: "#12ABEF"))
    store.setRepositoryColor(custom, for: "OWNER/REPO")
    requests = []
    await refresh(store)
    store.preferences.excludedRepositories = ["owner/repo"]
    let relaunched = AppStore(storageDirectory: directory)
    XCTAssertEqual(relaunched.preferences.repositoryColor(for: "owner/repo"), custom)
    XCTAssertEqual(relaunched.colorRepositories.count, 2)
    relaunched.assignRepositoryColors(for: ["new/repo", "owner/repo"])
    XCTAssertEqual(relaunched.preferences.repositoryColor(for: "new/repo"), RepositoryColor.presets[2].color)
    XCTAssertEqual(relaunched.preferences.repositoryColor(for: "owner/repo"), custom)
    requests = [pullRequest(repository: "owner/repo")]
    store.preferences.excludedRepositories = []
    await refresh(store)
    XCTAssertEqual(store.preferences.repositoryColor(for: "owner/repo"), custom)
  }

  func testLegacyCacheGetsPersistentColorsBeforeFirstNetworkRefresh() throws {
    let directory = storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let cache = GlanceCache(savedAt: .now, viewerLogin: "viewer", snapshots: [
      SectionSnapshot(id: Preferences.default.sections[0].id,
        pullRequests: [pullRequest(repository: "owner/repo")])
    ])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(cache).write(to: directory.appending(path: "cache.json"))
    let store = AppStore(storageDirectory: directory)
    XCTAssertEqual(store.preferences.repositoryColor(for: "owner/repo"), RepositoryColor.presets[0].color)
    XCTAssertEqual(AppStore(storageDirectory: directory).preferences.repositoryColors,
      store.preferences.repositoryColors)
  }

  func testColorSaveFailureIsVisibleAndSameColorRetries() throws {
    let directory = storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory)
    let file = directory.appending(path: "preferences.json")
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
    let custom = try XCTUnwrap(RepositoryColor(hex: "#12ABEF"))
    store.setRepositoryColor(custom, for: "owner/repo")
    XCTAssertNotNil(store.storageIssues["preferences.json-save"])
    try FileManager.default.removeItem(at: file)
    store.setRepositoryColor(custom, for: "owner/repo")
    XCTAssertNil(store.storageErrorMessage)
    XCTAssertEqual(AppStore(storageDirectory: directory).preferences.repositoryColor(for: "owner/repo"), custom)
  }

  func testInvalidStoredColorPreservesRecoveryCopyBeforeEditing() throws {
    let directory = storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let original = Data("{\"showAuthor\":false,\"repositoryColors\":{\"owner/repo\":\"invalid\"}}".utf8)
    let file = directory.appending(path: "preferences.json")
    try original.write(to: file)
    let store = AppStore(storageDirectory: directory)
    XCTAssertFalse(store.preferences.showAuthor)
    XCTAssertNotNil(store.storageErrorMessage)
    store.assignRepositoryColors(for: ["owner/repo"])
    let recovery = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory,
      includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("preferences.json.recovery-") })
    XCTAssertEqual(try Data(contentsOf: recovery), original)
    XCTAssertEqual(AppStore(storageDirectory: directory).preferences.repositoryColor(for: "owner/repo"),
      RepositoryColor.presets[0].color)
  }

  func testSettingsDeepLinkSelectsCategoryAndRepositoryRepeatedly() {
    let navigation = SettingsNavigation()
    navigation.showRepositoryColors(for: "Owner/Repo")
    XCTAssertEqual(navigation.category, .repoColors)
    XCTAssertEqual(navigation.repository, "owner/repo")
    let firstRequest = navigation.repositoryColorRequest
    navigation.category = .general
    navigation.showRepositoryColors(for: "Owner/Repo")
    XCTAssertEqual(navigation.category, .repoColors)
    XCTAssertGreaterThan(navigation.repositoryColorRequest, firstRequest)
    navigation.showRepositoryColors(for: "Other/Repo")
    XCTAssertEqual(navigation.repository, "other/repo")
  }

  private func storage() -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  }

  private func refresh(_ store: AppStore) async {
    store.refresh()
    for _ in 0..<1000 {
      if !store.isRefreshing { return }
      await Task.yield()
    }
    XCTFail("Refresh did not finish")
  }

  private func pullRequest(repository: String) -> PullRequest {
    PullRequest(id: repository, number: 1, repository: repository, title: "Test", author: "author",
      authorAvatarURL: nil, url: URL(string: "https://github.com/\(repository)/pull/1")!,
      branch: "feature", headRefOID: "abc123", createdAt: .now, reviewRequestedAt: nil,
      updatedAt: .now, isDraft: false, reviewDecision: nil, checksState: .success,
      additions: 1, deletions: 0, labels: [], requestedReviewers: [], viewerReviewState: nil,
      viewerReviewedHeadOID: nil, viewerReviewSubmittedAt: nil,
      hasCurrentApprovalFromOtherReviewer: false, stackPosition: nil, stackSize: nil,
      viewerDidAuthor: false, mergeState: nil, unresolvedConversationCount: 0, checks: nil,
      autoMergeEnabled: false, mergeQueuePosition: nil, lifecycleState: .open,
      viewerReviewRequested: false)
  }
}
