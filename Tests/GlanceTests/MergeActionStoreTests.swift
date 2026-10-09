import XCTest
@testable import Glance

@MainActor
final class MergeActionStoreTests: XCTestCase {
  func testAutoMergeUpdatesEverySectionAndSuppressesDoubleClicks() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = MergeGate()
    let pr = mergePullRequest()
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: [pr]) })
    }, performMergeAction: gate.perform)
    store.refresh()
    await finishRefresh(store)
    let first = Task { await store.performMergeAction(for: pr) }
    await gate.waitForRequest()
    XCTAssertTrue(store.mergingPullRequestIDs.contains(pr.id))
    XCTAssertFalse(store.snapshots.values.flatMap { $0 }.contains { $0.autoMergeEnabled == true })
    await store.performMergeAction(for: pr)
    XCTAssertEqual(gate.calls, [.enableAutoMerge])
    gate.pending?.resume(returning: .init(id: pr.id, lifecycleState: .open, autoMergeEnabled: true))
    await first.value
    XCTAssertTrue(store.mergingPullRequestIDs.isEmpty)
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy { $0.autoMergeEnabled == true })
    await store.performMergeAction(for: pr) // A stale row must not enable it twice.
    XCTAssertEqual(gate.calls.count, 1)
    let restored = AppStore(storageDirectory: directory)
    XCTAssertTrue(restored.snapshots.values.flatMap { $0 }.allSatisfy { $0.autoMergeEnabled == true })
  }

  func testFailedMergeKeepsStateAndAllowsRetry() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = MergeGate()
    let pr = mergePullRequest(mergeState: .clean)
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: [pr]) })
    }, performMergeAction: gate.perform)
    store.refresh()
    await finishRefresh(store)
    let first = Task { await store.performMergeAction(for: pr) }
    await gate.waitForRequest()
    gate.pending?.resume(throwing: GitHubError.api("Branch protection changed"))
    await first.value
    XCTAssertEqual(store.snapshots.values.first?.first?.lifecycleState, .open)
    XCTAssertEqual(store.mergeActionErrors[pr.id], "Branch protection changed")
    XCTAssertTrue(store.mergingPullRequestIDs.isEmpty)
    let retry = Task { await store.performMergeAction(for: pr) }
    await gate.waitForRequest(count: 2)
    XCTAssertNil(store.mergeActionErrors[pr.id])
    gate.pending?.resume(returning: .init(id: pr.id, lifecycleState: .merged, autoMergeEnabled: false))
    await retry.value
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy { $0.lifecycleState == .merged })
    XCTAssertEqual(PullRequestMergeControl(pullRequest: store.snapshots.values.first!.first!).state, .merged)
  }

  func testDisablingAutoMergeUpdatesAllSectionsOnlyAfterSuccessAndDeduplicatesClicks() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = MergeGate()
    let pr = mergePullRequest(autoMerge: true)
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: [pr]) })
    }, performMergeAction: gate.perform)
    store.refresh()
    await finishRefresh(store)
    let failed = Task { await store.performMergeAction(for: pr) }
    await gate.waitForRequest()
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy { $0.autoMergeEnabled == true })
    gate.pending?.resume(throwing: GitHubError.api("Disable failed"))
    await failed.value
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy { $0.autoMergeEnabled == true })
    let retry = Task { await store.performMergeAction(for: pr) }
    await gate.waitForRequest(count: 2)
    await store.performMergeAction(for: pr)
    XCTAssertEqual(gate.calls, [.disableAutoMerge, .disableAutoMerge])
    gate.pending?.resume(returning: .init(id: pr.id, lifecycleState: .open, autoMergeEnabled: false))
    await retry.value
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy { $0.autoMergeEnabled == false })
    XCTAssertNil(store.mergeActionErrors[pr.id])
    XCTAssertTrue(store.mergingPullRequestIDs.isEmpty)
    await store.performMergeAction(for: pr) // A stale green icon must not enable it again.
    XCTAssertEqual(gate.calls.count, 2)
    let restored = AppStore(storageDirectory: directory)
    XCTAssertTrue(restored.snapshots.values.flatMap { $0 }.allSatisfy { $0.autoMergeEnabled == false })
  }

  func testMarkReadyForReviewPreservesDraftOnFailureThenUpdatesEverySectionAndRefreshes() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = MergeGate()
    let fetch = MergeRefreshGate()
    let draft = mergePullRequest(mergeState: .clean, draft: true, headOID: nil)
    let store = AppStore(storageDirectory: directory, fetchSnapshots: fetch.fetch, performMergeAction: gate.perform)
    store.refresh()
    await fetch.waitForRequest(1)
    fetch.complete(draft)
    await finishRefresh(store)
    let failed = Task { await store.performMergeAction(for: draft) }
    await gate.waitForRequest()
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy(\.isDraft))
    gate.pending?.resume(throwing: GitHubError.api("Ready-for-review permission revoked"))
    await failed.value
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy(\.isDraft))
    XCTAssertNotNil(store.mergeActionErrors[draft.id])
    let retry = Task { await store.performMergeAction(for: draft) }
    await gate.waitForRequest(count: 2)
    await store.performMergeAction(for: draft)
    XCTAssertEqual(gate.calls, [.markReadyForReview, .markReadyForReview])
    gate.pending?.resume(returning: .init(id: draft.id, lifecycleState: .open, autoMergeEnabled: false, isDraft: false))
    await retry.value
    await fetch.waitForRequest(2)
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy { !$0.isDraft })
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy { $0.isMergeable == nil })
    XCTAssertNil(store.mergeActionErrors[draft.id])
    XCTAssertTrue(store.mergingPullRequestIDs.isEmpty)
    let readyForReview = mergePullRequest()
    fetch.complete(readyForReview)
    await finishRefresh(store)
    await store.performMergeAction(for: draft) // A stale draft icon must not enable auto-merge or merge.
    XCTAssertEqual(gate.calls.count, 2)
    let restored = AppStore(storageDirectory: directory)
    XCTAssertTrue(restored.snapshots.values.flatMap { $0 }.allSatisfy { !$0.isDraft })
  }

  func testRefreshStartedBeforeSuccessfulMutationCannotRevertItsState() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = MergeGate()
    let fetch = MergeRefreshGate()
    let pr = mergePullRequest(mergeState: .clean)
    let store = AppStore(storageDirectory: directory, fetchSnapshots: fetch.fetch, performMergeAction: gate.perform)
    store.refresh()
    await fetch.waitForRequest(1)
    fetch.complete(pr)
    await finishRefresh(store)
    store.refresh()
    await fetch.waitForRequest(2)
    let action = Task { await store.performMergeAction(for: pr) }
    await gate.waitForRequest()
    gate.pending?.resume(returning: .init(id: pr.id, lifecycleState: .merged, autoMergeEnabled: false))
    await action.value
    fetch.complete(pr) // Obsolete OPEN response.
    await fetch.waitForRequest(3)
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy { $0.lifecycleState == .merged })
    var merged = pr
    merged.lifecycleState = .merged
    fetch.complete(merged)
    await finishRefresh(store)
  }

  func testUnavailableOrRemovedPullRequestDoesNotMutate() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = MergeGate()
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { _ in ("viewer", []) }, performMergeAction: gate.perform)
    await store.performMergeAction(for: mergePullRequest())
    XCTAssertTrue(gate.calls.isEmpty)
  }

  func testStaleClickCannotEscalateFromAutoMergeToMergeOrMergeNewCommits() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = MergeGate()
    let ready = mergePullRequest(mergeState: .clean, headOID: "new-commit")
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: [ready]) })
    }, performMergeAction: gate.perform)
    store.refresh()
    await finishRefresh(store)
    await store.performMergeAction(for: mergePullRequest(headOID: "new-commit"))
    XCTAssertTrue(gate.calls.isEmpty)
    XCTAssertNotNil(store.mergeActionErrors[ready.id])
    await store.performMergeAction(for: mergePullRequest(mergeState: .clean))
    XCTAssertTrue(gate.calls.isEmpty)
    XCTAssertNotNil(store.mergeActionErrors[ready.id])
    await store.performMergeAction(for: mergePullRequest(autoMerge: true, headOID: "new-commit"))
    XCTAssertTrue(gate.calls.isEmpty, "A stale green PR icon must not escalate disable into merge")
    await store.performMergeAction(for: mergePullRequest(draft: true, headOID: "new-commit"))
    XCTAssertTrue(gate.calls.isEmpty, "A stale draft icon must not escalate ready-for-review into merge")
  }

  func testDisablingRemainsSafeAfterNewCommits() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = MergeGate()
    let current = mergePullRequest(autoMerge: true, headOID: "new-commit")
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: [current]) })
    }, performMergeAction: gate.perform)
    store.refresh()
    await finishRefresh(store)
    let disable = Task { await store.performMergeAction(for: mergePullRequest(autoMerge: true)) }
    await gate.waitForRequest()
    XCTAssertEqual(gate.calls, [.disableAutoMerge])
    gate.pending?.resume(returning: .init(id: current.id, lifecycleState: .open, autoMergeEnabled: false))
    await disable.value
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy { $0.autoMergeEnabled == false })
  }

  func testRateLimitedMutationPausesFurtherActionsAndRemovedRowsClearErrors() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = MergeGate()
    let pr = mergePullRequest()
    var requests = [pr]
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: requests) })
    }, performMergeAction: gate.perform)
    store.refresh()
    await finishRefresh(store)
    let task = Task { await store.performMergeAction(for: pr) }
    await gate.waitForRequest()
    let deadline = Date().addingTimeInterval(0.05)
    gate.pending?.resume(throwing: GitHubError.rateLimited(until: deadline))
    await task.value
    XCTAssertEqual(store.refreshBlockedUntil, deadline)
    await store.performMergeAction(for: pr)
    XCTAssertEqual(gate.calls.count, 1)
    requests = []
    try await Task.sleep(for: .milliseconds(60))
    store.refresh()
    await finishRefresh(store)
    XCTAssertTrue(store.mergeActionErrors.isEmpty)
  }

  private func storage() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func finishRefresh(_ store: AppStore) async {
    for _ in 0..<1000 {
      if !store.isRefreshing { return }
      await Task.yield()
    }
    XCTFail("Refresh did not finish")
  }
}

@MainActor
private final class MergeGate {
  var calls: [PullRequestMergeAction] = []
  var pending: CheckedContinuation<PullRequestMergeResult, Error>?

  func perform(_ action: PullRequestMergeAction, _ pr: PullRequest) async throws -> PullRequestMergeResult {
    calls.append(action)
    return try await withCheckedThrowingContinuation { pending = $0 }
  }

  func waitForRequest(count: Int = 1) async {
    for _ in 0..<1000 {
      if calls.count >= count && pending != nil { return }
      await Task.yield()
    }
    XCTFail("Mutation did not start")
  }
}

@MainActor
private final class MergeRefreshGate {
  var requests = 0
  var sections: [PRSection] = []
  var pending: CheckedContinuation<(viewer: String, snapshots: [SectionSnapshot]), Error>?

  func fetch(_ sections: [PRSection]) async throws -> (viewer: String, snapshots: [SectionSnapshot]) {
    requests += 1
    self.sections = sections
    return try await withCheckedThrowingContinuation { pending = $0 }
  }

  func complete(_ pr: PullRequest) {
    pending?.resume(returning: ("viewer", sections.map { .init(id: $0.id, pullRequests: [pr]) }))
    pending = nil
  }

  func waitForRequest(_ count: Int) async {
    for _ in 0..<1000 {
      if requests >= count && pending != nil { return }
      await Task.yield()
    }
    XCTFail("Refresh did not start")
  }
}
