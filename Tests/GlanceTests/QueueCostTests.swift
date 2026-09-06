import XCTest
@testable import Glance

@MainActor
final class QueueCostTests: XCTestCase {
  func testQueueCostDiagnostic() async throws {
    guard ProcessInfo.processInfo.environment["GLANCE_BENCHMARK"] == "1" else {
      throw XCTSkip("Opt in with GLANCE_BENCHMARK=1; no network or normal profile is used.")
    }
    for count in [100, 1000, 5000] {
      let rows = (0..<count).map { makePullRequest(id: "PR_\($0)") }
      let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
        ("fixture", sections.map { SectionSnapshot(id: $0.id, pullRequests: rows) })
      })
      store.preferences.sections = (0..<5).map { PRSection(name: "Section \($0)", query: "is:pr") }
      store.preferences.notificationEvents = []
      var samples: [Double] = []
      for _ in 0..<5 {
        let start = ProcessInfo.processInfo.systemUptime
        store.refresh()
        while store.isRefreshing { await Task.yield() }
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.pullRequests(in: store.preferences.sections[0]).count, count)
        samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
      }
      let cache = try Data(contentsOf: directory.appending(path: "cache.json"))
      let start = ProcessInfo.processInfo.systemUptime
      let navigation = DashboardNavigation(sections: store.preferences.sections.map { ($0, store.pullRequests(in: $0)) }, query: "Test")
      let navigationMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
      XCTAssertEqual(navigation.rows.count, count * 5)
      print("QUEUE_COST unique=\(count) occurrences=\(count * 5) refresh_median_ms=\(samples.sorted()[2]) navigation_ms=\(navigationMS) cache_bytes=\(cache.count)")
    }
  }

  private func makePullRequest(id: String = "PR_1", repository: String = "owner/repo") -> PullRequest {
    PullRequest(
      id: id, number: 1, repository: repository, title: "Test", author: "author",
      authorAvatarURL: nil, url: URL(string: "https://github.com/owner/repo/pull/1")!,
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
