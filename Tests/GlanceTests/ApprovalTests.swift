import Foundation
import XCTest
@testable import Glance

final class ApprovalEligibilityTests: XCTestCase {
  func testOnlyOpenPullRequestsByOthersCanBeApproved() {
    XCTAssertTrue(mergePullRequest().canApprove)
    XCTAssertFalse(mergePullRequest(authored: true).canApprove, "GitHub forbids approving your own PR")
    XCTAssertTrue(mergePullRequest(draft: true).canApprove, "GitHub accepts approvals of drafts")
    XCTAssertFalse(mergePullRequest(lifecycle: .closed).canApprove)
    XCTAssertFalse(mergePullRequest(lifecycle: .merged).canApprove)
    XCTAssertFalse(mergePullRequest(lifecycle: nil).canApprove)
    XCTAssertFalse(mergePullRequest(headOID: nil).canApprove, "Approval must pin the displayed commit")
  }

  func testUnknownAuthorshipFromOlderCachesIsNotApprovable() {
    XCTAssertFalse(mergePullRequest(authored: nil).canApprove)
  }

  func testApprovalAtTheCurrentHeadIsNotRepeatedButNewCommitsCanBeApproved() {
    var pr = mergePullRequest()
    pr.viewerReviewState = "APPROVED"
    pr.viewerReviewedHeadOID = pr.headRefOID
    XCTAssertFalse(pr.canApprove)
    pr.viewerReviewedHeadOID = "older"
    XCTAssertTrue(pr.canApprove)
    pr.viewerReviewState = "CHANGES_REQUESTED"
    pr.viewerReviewedHeadOID = pr.headRefOID
    XCTAssertTrue(pr.canApprove, "A reviewer can replace their change request with an approval")
  }
}

final class GitHubApprovalTests: XCTestCase {
  func testApprovalSubmitsAnApproveReviewPinnedToTheDisplayedHead() async throws {
    for draft in [false, true] { try await assertApprovalSubmitted(mergePullRequest(draft: draft)) }
  }

  private func assertApprovalSubmitted(_ pr: PullRequest) async throws {
    let result = try await withClient { client in
      ApprovalURLProtocol.handler = { request in
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
        let payload = try self.payload(request)
        let query = payload["query"] as! String
        if query.contains("GlanceApprovalHead") {
          XCTAssertEqual((payload["variables"] as! [String: String])["id"], pr.id)
          return (200, self.headResponse(id: pr.id, head: "abc123"))
        }
        XCTAssertTrue(query.contains("addPullRequestReview"))
        XCTAssertTrue(query.contains("AddPullRequestReviewInput"))
        let input = (payload["variables"] as! [String: Any])["input"] as! [String: String]
        XCTAssertEqual(input, ["pullRequestId": pr.id, "commitOID": "abc123", "event": "APPROVE"])
        return (200, self.response(id: pr.id, state: "APPROVED", commit: "abc123"))
      }
      return try await client.approve(pr)
    }
    XCTAssertEqual(result.id, pr.id)
    XCTAssertEqual(result.headOID, "abc123")
    XCTAssertEqual(result.submittedAt, ISO8601DateFormatter().date(from: "2026-10-19T10:00:00Z"))
  }

  func testUnconfirmedOrFailedApprovalsAreRejected() async throws {
    let responses: [(Int, Data, String?)] = [
      (200, Data(#"{"errors":[{"message":"Can not approve your own pull request"}]}"#.utf8),
       "Can not approve your own pull request"),
      (403, Data(#"{"message":"Resource not accessible"}"#.utf8), "Resource not accessible"),
      (200, Data(#"{"data":{"result":null}}"#.utf8), nil),
      (200, response(id: "other-pr", state: "APPROVED", commit: "abc123"), nil),
      (200, response(id: "PR_merge", state: "PENDING", commit: "abc123"), nil),
      (200, response(id: "PR_merge", state: "APPROVED", commit: "newer"), nil),
    ]
    for (status, data, message) in responses {
      try await withClient { client in
        ApprovalURLProtocol.handler = { request in
          if (try self.payload(request)["query"] as! String).contains("GlanceApprovalHead") {
            return (200, self.headResponse(id: "PR_merge", head: "abc123"))
          }
          return (status, data)
        }
        do {
          _ = try await client.approve(mergePullRequest())
          XCTFail("Unconfirmed approval must fail")
        } catch {
          if let message { XCTAssertEqual(error.localizedDescription, message) }
        }
      }
    }
  }

  func testIneligiblePullRequestsNeverIssueARequest() async throws {
    try await withClient { client in
      ApprovalURLProtocol.handler = { _ in XCTFail("Unexpected mutation"); return (500, Data()) }
      for pr in [mergePullRequest(authored: true), mergePullRequest(lifecycle: .merged),
                 mergePullRequest(headOID: nil)] {
        do {
          _ = try await client.approve(pr)
          XCTFail("Ineligible PR must not be approved")
        } catch {}
      }
    }
  }

  func testRemoteHeadChangeOrUnconfirmedHeadNeverSubmitsApproval() async throws {
    let responses: [(Int, Data, String?)] = [
      (200, headResponse(id: "PR_merge", head: "newer"),
       "Pull request changed. Refresh before trying again."),
      (200, headResponse(id: "other-pr", head: "abc123"), nil),
      (200, Data(#"{"data":{"node":null}}"#.utf8), nil),
      (200, Data(#"{"errors":[{"message":"Access denied"}]}"#.utf8), "Access denied"),
      (403, Data(#"{"message":"Resource not accessible"}"#.utf8), nil),
    ]
    for (status, data, message) in responses {
      try await withClient { client in
        ApprovalURLProtocol.handler = { request in
          XCTAssertFalse((try self.payload(request)["query"] as! String).contains("addPullRequestReview"),
            "A failed head check must not submit a review")
          return (status, data)
        }
        do {
          _ = try await client.approve(mergePullRequest())
          XCTFail("An unconfirmed remote head must not be approved")
        } catch {
          if let message { XCTAssertEqual(error.localizedDescription, message) }
        }
      }
    }
  }

  private func headResponse(id: String, head: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["data": ["node": ["id": id, "headRefOid": head]]])
  }

  private func response(id: String, state: String, commit: String) -> Data {
    let review: [String: Any] = ["state": state, "submittedAt": "2026-10-19T10:00:00Z",
      "commit": ["oid": commit], "pullRequest": ["id": id]]
    return try! JSONSerialization.data(withJSONObject: ["data": ["result": ["pullRequestReview": review]]])
  }

  private func payload(_ request: URLRequest) throws -> [String: Any] {
    var body = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var bytes = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&bytes, maxLength: bytes.count)
        if count <= 0 { break }
        body.append(contentsOf: bytes.prefix(count))
      }
    }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
  }

  private func withClient<T>(_ operation: (GitHubClient) async throws -> T) async throws -> T {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ApprovalURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel(); ApprovalURLProtocol.handler = nil }
    return try await operation(
      GitHubClient(session: GitHubSession(credentialProvider: ApprovalCredentials()), urlSession: session))
  }
}

@MainActor
final class ApprovalStoreTests: XCTestCase {
  func testApprovalUpdatesEverySectionAndSuppressesDoubleClicks() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = ApprovalGate()
    let pr = mergePullRequest()
    let refreshes = RefreshCounter()
    var served = pr
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      await refreshes.increment()
      return ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: [served]) })
    }, approvePullRequest: gate.approve)
    store.refresh()
    await finishRefresh(store)
    store.preferences.pinnedPullRequests.insert(pr.id)
    let first = Task { await store.approve(pr) }
    await gate.waitForRequest()
    XCTAssertTrue(store.approvingPullRequestIDs.contains(pr.id))
    await store.approve(pr)
    XCTAssertEqual(gate.calls, 1)
    let submittedAt = Date(timeIntervalSince1970: 1_800_000_000)
    served.viewerReviewState = "APPROVED"
    served.viewerReviewedHeadOID = "abc123"
    served.viewerReviewSubmittedAt = submittedAt
    gate.pending?.resume(returning: .init(id: pr.id, headOID: "abc123", submittedAt: submittedAt))
    await first.value
    XCTAssertTrue(store.approvingPullRequestIDs.isEmpty)
    let updated = store.snapshots.values.flatMap { $0 }
    XCTAssertFalse(updated.isEmpty)
    XCTAssertTrue(updated.allSatisfy {
      $0.viewerReviewState == "APPROVED" && $0.viewerReviewedHeadOID == "abc123"
        && $0.viewerReviewSubmittedAt == submittedAt && !$0.canApprove
    })
    await store.approve(pr) // A stale menu must not approve twice.
    XCTAssertEqual(gate.calls, 1)
    let restored = AppStore(storageDirectory: directory)
    let cached = restored.snapshots.values.flatMap { $0 }
    XCTAssertFalse(cached.isEmpty)
    XCTAssertTrue(cached.allSatisfy {
      $0.id == pr.id && $0.viewerReviewState == "APPROVED"
        && $0.viewerReviewedHeadOID == "abc123" && $0.viewerReviewSubmittedAt == submittedAt
    })
    await finishRefresh(store)
    await store.approve(pr)
    XCTAssertEqual(gate.calls, 1, "A confirmed follow-up read must keep the approval ineligible")
    let refreshCount = await refreshes.count
    XCTAssertEqual(refreshCount, 2, "Approval refreshes so GitHub's review decision and requests catch up")
  }

  func testFailedApprovalKeepsStateReportsErrorAndAllowsRetry() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = ApprovalGate()
    let pr = mergePullRequest()
    var served = pr
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: [served]) })
    }, approvePullRequest: gate.approve)
    store.refresh()
    await finishRefresh(store)
    let first = Task { await store.approve(pr) }
    await gate.waitForRequest()
    gate.pending?.resume(throwing: GitHubError.api("Review permission required"))
    await first.value
    XCTAssertNil(store.snapshots.values.first?.first?.viewerReviewState)
    XCTAssertEqual(store.approvalErrors[pr.id], "Review permission required")
    let retry = Task { await store.approve(pr) }
    await gate.waitForRequest(count: 2)
    XCTAssertNil(store.approvalErrors[pr.id])
    served.viewerReviewState = "APPROVED"
    served.viewerReviewedHeadOID = "abc123"
    gate.pending?.resume(returning: .init(id: pr.id, headOID: "abc123", submittedAt: .now))
    await retry.value
    await finishRefresh(store)
    XCTAssertNil(store.approvalErrors[pr.id])
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy { $0.viewerReviewState == "APPROVED" })
  }

  func testRefreshStartedBeforeApprovalCannotRevertIt() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = ApprovalGate()
    let pr = mergePullRequest()
    var fetches: [CheckedContinuation<(viewer: String, snapshots: [SectionSnapshot]), Error>] = []
    var sections: [PRSection] = []
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { requested in
      sections = requested
      return try await withCheckedThrowingContinuation { fetches.append($0) }
    }, approvePullRequest: gate.approve)
    func completeFetch() {
      fetches.removeFirst().resume(returning: ("viewer", sections.map { .init(id: $0.id, pullRequests: [pr]) }))
    }
    store.refresh()
    while fetches.isEmpty { await Task.yield() }
    completeFetch()
    await finishRefresh(store)
    store.refresh()
    while fetches.isEmpty { await Task.yield() }
    let approval = Task { await store.approve(pr) }
    await gate.waitForRequest()
    gate.pending?.resume(returning: .init(id: pr.id, headOID: "abc123", submittedAt: .now))
    await approval.value
    completeFetch() // Stale: began before the approval.
    for _ in 0..<1000 where fetches.isEmpty { await Task.yield() }
    XCTAssertTrue(store.snapshots.values.flatMap { $0 }.allSatisfy { $0.viewerReviewState == "APPROVED" })
    XCTAssertEqual(fetches.count, 1, "A fresh refresh is queued after the approval")
    fetches.removeFirst().resume(throwing: CancellationError())
  }

  func testStaleMenuCannotApproveNewerCommits() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = ApprovalGate()
    let current = mergePullRequest(headOID: "new-commit")
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: [current]) })
    }, approvePullRequest: gate.approve)
    store.refresh()
    await finishRefresh(store)
    await store.approve(mergePullRequest())
    XCTAssertEqual(gate.calls, 0)
    XCTAssertEqual(store.approvalErrors[current.id], "Pull request changed. Refresh before trying again.")
  }

  func testRemovedRowsClearApprovalErrors() async throws {
    let directory = try storage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = ApprovalGate()
    let pr = mergePullRequest()
    var requests = [pr]
    let store = AppStore(storageDirectory: directory, fetchSnapshots: { sections in
      ("viewer", sections.map { SectionSnapshot(id: $0.id, pullRequests: requests) })
    }, approvePullRequest: gate.approve)
    store.refresh()
    await finishRefresh(store)
    let task = Task { await store.approve(pr) }
    await gate.waitForRequest()
    gate.pending?.resume(throwing: GitHubError.api("Nope"))
    await task.value
    XCTAssertNotNil(store.approvalErrors[pr.id])
    requests = []
    store.refresh()
    await finishRefresh(store)
    XCTAssertTrue(store.approvalErrors.isEmpty)
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

private actor RefreshCounter {
  var count = 0
  func increment() { count += 1 }
}

@MainActor
private final class ApprovalGate {
  var calls = 0
  var pending: CheckedContinuation<PullRequestApprovalResult, Error>?

  func approve(_ pr: PullRequest) async throws -> PullRequestApprovalResult {
    calls += 1
    return try await withCheckedThrowingContinuation { pending = $0 }
  }

  func waitForRequest(count: Int = 1) async {
    for _ in 0..<1000 {
      if calls >= count && pending != nil { return }
      await Task.yield()
    }
    XCTFail("Approval did not start")
  }
}

private struct ApprovalCredentials: GitHubCredentialProvider {
  func credential() async throws -> GitHubCredential { .init(accessToken: "fixture") }
}

private final class ApprovalURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, data) = try XCTUnwrap(Self.handler)(request)
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
