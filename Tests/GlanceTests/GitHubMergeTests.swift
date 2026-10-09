import Foundation
import XCTest
@testable import Glance

final class GitHubMergeTests: XCTestCase {
  func testEnableAutoMergeUsesAuthenticatedGraphQLMutationAndAllowedMethod() async throws {
    for method in [PullRequest.MergeMethod.squash, .merge, .rebase] {
      var pr = mergePullRequest()
      pr.mergeCapabilities?.preferredMethod = method
      let result = try await withClient { client in
        MergeURLProtocol.handler = { request in
          XCTAssertEqual(request.httpMethod, "POST")
          XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
          let payload = try self.payload(request)
          XCTAssertTrue((payload["query"] as! String).contains("enablePullRequestAutoMerge"))
          let input = (payload["variables"] as! [String: Any])["input"] as! [String: String]
          XCTAssertEqual(input, ["pullRequestId": pr.id, "mergeMethod": method.rawValue.uppercased(),
            "expectedHeadOid": "abc123"])
          return (200, self.response(id: pr.id, merged: false, autoMerge: true))
        }
        return try await client.performMergeAction(.enableAutoMerge, on: pr)
      }
      XCTAssertTrue(result.autoMergeEnabled)
      XCTAssertEqual(result.lifecycleState, .open)
    }
  }

  func testDirectMergeGuardsExpectedHeadCommit() async throws {
    let pr = mergePullRequest(mergeState: .clean)
    let result = try await withClient { client in
      MergeURLProtocol.handler = { request in
        let payload = try self.payload(request)
        XCTAssertTrue((payload["query"] as! String).contains("mergePullRequest"))
        let input = (payload["variables"] as! [String: Any])["input"] as! [String: String]
        XCTAssertEqual(input["pullRequestId"], pr.id)
        XCTAssertEqual(input["expectedHeadOid"], pr.headRefOID)
        XCTAssertEqual(input["mergeMethod"], "SQUASH")
        return (200, self.response(id: pr.id, merged: true, autoMerge: false))
      }
      return try await client.performMergeAction(.merge, on: pr)
    }
    XCTAssertEqual(result.id, pr.id)
    XCTAssertEqual(result.lifecycleState, .merged)
    XCTAssertFalse(result.autoMergeEnabled)
  }

  func testMarkReadyForReviewUsesIDOnlyAndRequiresConfirmedNonDraftState() async throws {
    var pr = mergePullRequest(draft: true, headOID: nil)
    pr.mergeCapabilities?.preferredMethod = nil
    try await withClient { client in
      MergeURLProtocol.handler = { request in
        let payload = try self.payload(request)
        let query = payload["query"] as! String
        XCTAssertTrue(query.contains("markPullRequestReadyForReview"))
        XCTAssertTrue(query.contains("MarkPullRequestReadyForReviewInput"))
        XCTAssertTrue(query.contains("isDraft"))
        let input = (payload["variables"] as! [String: Any])["input"] as! [String: String]
        XCTAssertEqual(input, ["pullRequestId": pr.id])
        return (200, self.response(id: pr.id, merged: false, autoMerge: false))
      }
      let result = try await client.performMergeAction(.markReadyForReview, on: pr)
      XCTAssertEqual(result.isDraft, false)
      XCTAssertEqual(result.lifecycleState, .open)
      MergeURLProtocol.handler = { _ in (200, self.response(id: pr.id, merged: false, autoMerge: false, draft: true)) }
      do {
        _ = try await client.performMergeAction(.markReadyForReview, on: pr)
        XCTFail("An unchanged draft is not a successful ready-for-review mutation")
      } catch {}
      MergeURLProtocol.handler = { _ in (200, self.response(id: pr.id, merged: true, autoMerge: false)) }
      do {
        _ = try await client.performMergeAction(.markReadyForReview, on: pr)
        XCTFail("A merged PR is not ready for review")
      } catch {}
    }
  }

  func testDisableAutoMergeUsesOnlyPullRequestIDAndVerifiesTheReturnedState() async throws {
    var pr = mergePullRequest(autoMerge: true, headOID: nil)
    pr.mergeCapabilities?.preferredMethod = nil
    try await withClient { client in
      MergeURLProtocol.handler = { request in
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
        let payload = try self.payload(request)
        let query = payload["query"] as! String
        XCTAssertTrue(query.contains("DisablePullRequestAutoMergeInput"))
        XCTAssertTrue(query.contains("disablePullRequestAutoMerge"))
        let input = (payload["variables"] as! [String: Any])["input"] as! [String: String]
        XCTAssertEqual(input, ["pullRequestId": pr.id])
        return (200, self.response(id: pr.id, merged: false, autoMerge: false))
      }
      let result = try await client.performMergeAction(.disableAutoMerge, on: pr)
      XCTAssertFalse(result.autoMergeEnabled)
      XCTAssertEqual(result.lifecycleState, .open)
      MergeURLProtocol.handler = { _ in (200, self.response(id: pr.id, merged: false, autoMerge: true)) }
      do {
        _ = try await client.performMergeAction(.disableAutoMerge, on: pr)
        XCTFail("An unchanged enabled request is not success")
      } catch {}
      MergeURLProtocol.handler = { _ in (200, Data(#"{"errors":[{"message":"Disable permission revoked"}]}"#.utf8)) }
      do {
        _ = try await client.performMergeAction(.disableAutoMerge, on: pr)
        XCTFail("Permission failures must propagate")
      } catch { XCTAssertEqual(error.localizedDescription, "Disable permission revoked") }
    }
  }

  func testAutoMergeAcceptsAnImmediateMergeButNotAnUnchangedOpenPullRequest() async throws {
    try await withClient { client in
      MergeURLProtocol.handler = { _ in (200, self.response(id: "PR_merge", merged: true, autoMerge: false)) }
      let result = try await client.performMergeAction(.enableAutoMerge, on: mergePullRequest())
      XCTAssertEqual(result.lifecycleState, .merged)
      MergeURLProtocol.handler = { _ in (200, self.response(id: "PR_merge", merged: false, autoMerge: false)) }
      do {
        _ = try await client.performMergeAction(.enableAutoMerge, on: mergePullRequest())
        XCTFail("Unchanged PR must not be reported as auto-merge enabled")
      } catch {}
    }
  }

  func testAuthenticationAndRateLimitFailuresArePreservedForMergeActions() async throws {
    for status in [401, 429] {
      try await withClient { client in
        MergeURLProtocol.handler = { _ in (status, Data(#"{"message":"Request rejected"}"#.utf8)) }
        do {
          _ = try await client.performMergeAction(.enableAutoMerge, on: mergePullRequest())
          XCTFail("Rejected request must fail")
        } catch let error as GitHubError {
          switch error {
          case .notAuthenticated: XCTAssertEqual(status, 401)
          case .rateLimited: XCTAssertEqual(status, 429)
          default: XCTFail("Wrong GitHub error: \(error)")
          }
        }
      }
    }
  }

  func testUnavailableActionsNeverIssueANetworkRequest() async throws {
    try await withClient { client in
      MergeURLProtocol.handler = { _ in XCTFail("Unexpected mutation"); return (500, Data()) }
      do {
        _ = try await client.performMergeAction(.merge, on: mergePullRequest())
        XCTFail("Blocked PR must not be merged")
      } catch {}
      do {
        _ = try await client.performMergeAction(.enableAutoMerge, on: mergePullRequest(lifecycle: .closed))
        XCTFail("Closed PR must not enable auto-merge")
      } catch {}
    }
  }

  func testMutationErrorsAndUnconfirmedSuccessAreNotAccepted() async throws {
    let responses: [(Int, Data)] = [
      (200, Data(#"{"errors":[{"message":"Branch protection changed"}]}"#.utf8)),
      (403, Data(#"{"message":"Write permission required"}"#.utf8)),
      (200, Data(#"{"data":{"result":null}}"#.utf8)),
      (200, response(id: "different-pr", merged: true, autoMerge: false)),
      (200, response(id: "PR_merge", merged: false, autoMerge: false)),
    ]
    for (status, data) in responses {
      try await withClient { client in
        MergeURLProtocol.handler = { _ in (status, data) }
        do {
          _ = try await client.performMergeAction(.merge, on: mergePullRequest(mergeState: .clean))
          XCTFail("Unconfirmed mutation must fail")
        } catch {
          if status == 403 { XCTAssertEqual(error.localizedDescription, "Write permission required") }
        }
      }
    }
  }

  func testSectionFetchIncludesRepositoryCapabilitiesAndPermission() async throws {
    for permission: String? in ["ADMIN", "MAINTAIN", "WRITE", "TRIAGE", "READ", nil] {
      for allowed: [Bool] in [[true, true, true], [false, true, false], [false, false, true], [false, false, false]] {
        let pr = try await withClient { client in
          MergeURLProtocol.handler = { request in
            let query = try self.payload(request)["query"] as! String
            for field in ["autoMergeAllowed", "viewerCanEnableAutoMerge", "viewerCanDisableAutoMerge", "viewerPermission",
              "squashMergeAllowed", "mergeCommitAllowed", "rebaseMergeAllowed"] {
              XCTAssertTrue(query.contains(field), "Missing field: \(field)")
            }
            let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
              .appending(path: "Fixtures/personal-review-section.json")
            var fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
            var graph = fixture["data"] as! [String: Any]
            var search = graph["search"] as! [String: Any]
            var node = (search["nodes"] as! [[String: Any]])[0]
            node["repository"] = ["nameWithOwner": "owner/repo", "autoMergeAllowed": false,
              "viewerPermission": permission.map { $0 as Any } ?? NSNull(), "squashMergeAllowed": allowed[0],
              "mergeCommitAllowed": allowed[1], "rebaseMergeAllowed": allowed[2]]
            node["viewerCanEnableAutoMerge"] = false
            node["viewerCanDisableAutoMerge"] = true
            node["mergeable"] = "MERGEABLE"
            search["nodes"] = [node]; graph["search"] = search; fixture["data"] = graph
            return (200, try JSONSerialization.data(withJSONObject: fixture))
          }
          let result = try await client.fetchAll(sections: [PRSection(name: "Test", query: "is:pr")])
          return try XCTUnwrap(result.snapshots.first?.pullRequests.first)
        }
        XCTAssertEqual(pr.isMergeable, true)
        XCTAssertEqual(pr.mergeCapabilities?.autoMergeAllowed, false)
        XCTAssertEqual(pr.mergeCapabilities?.viewerCanEnableAutoMerge, false)
        XCTAssertEqual(pr.mergeCapabilities?.viewerCanDisableAutoMerge, true)
        XCTAssertEqual(pr.mergeCapabilities?.viewerCanMerge, ["ADMIN", "MAINTAIN", "WRITE"].contains(permission ?? ""))
        let expected: PullRequest.MergeMethod? = allowed[0] ? .squash : allowed[1] ? .merge : allowed[2] ? .rebase : nil
        XCTAssertEqual(pr.mergeCapabilities?.preferredMethod, expected)
      }
    }
  }

  func testReadyForReviewPermissionAllowsAuthorsAndWritersButNotTriageOrUnknownUpdateAccess() async throws {
    for permission in ["WRITE", "MAINTAIN", "ADMIN", "TRIAGE", "READ"] {
      for authored in [false, true] {
        for canUpdate: Bool? in [true, false, nil] {
          let pr = try await withClient { client in
            MergeURLProtocol.handler = { request in
              let query = try self.payload(request)["query"] as! String
              XCTAssertTrue(query.contains("viewerCanUpdate"))
              let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appending(path: "Fixtures/personal-review-section.json")
              var fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
              var graph = fixture["data"] as! [String: Any]
              var search = graph["search"] as! [String: Any]
              var node = (search["nodes"] as! [[String: Any]])[0]
              node["repository"] = ["nameWithOwner": "owner/repo", "autoMergeAllowed": false,
                "viewerPermission": permission, "squashMergeAllowed": false,
                "mergeCommitAllowed": false, "rebaseMergeAllowed": false]
              node["viewerDidAuthor"] = authored
              node["viewerCanUpdate"] = canUpdate
              node["isDraft"] = true
              search["nodes"] = [node]; graph["search"] = search; fixture["data"] = graph
              return (200, try JSONSerialization.data(withJSONObject: fixture))
            }
            let result = try await client.fetchAll(sections: [PRSection(name: "Test", query: "is:pr")])
            return try XCTUnwrap(result.snapshots.first?.pullRequests.first)
          }
          let expected = canUpdate == true && (authored || ["WRITE", "MAINTAIN", "ADMIN"].contains(permission))
          XCTAssertEqual(PullRequestMergeControl(pullRequest: pr).action == .markReadyForReview, expected)
        }
      }
    }
  }

  private func response(id: String, merged: Bool, autoMerge: Bool, draft: Bool = false) -> Data {
    let pr: [String: Any] = ["id": id, "state": merged ? "MERGED" : "OPEN", "merged": merged, "isDraft": draft,
      "autoMergeRequest": autoMerge ? ["enabledAt": "2026-10-09T10:00:00Z"] : NSNull()]
    return try! JSONSerialization.data(withJSONObject: ["data": ["result": ["pullRequest": pr]]])
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
    configuration.protocolClasses = [MergeURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel(); MergeURLProtocol.handler = nil }
    return try await operation(GitHubClient(session: GitHubSession(credentialProvider: MergeCredentials()), urlSession: session))
  }
}

private struct MergeCredentials: GitHubCredentialProvider {
  func credential() async throws -> GitHubCredential { .init(accessToken: "fixture") }
}

private final class MergeURLProtocol: URLProtocol {
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
