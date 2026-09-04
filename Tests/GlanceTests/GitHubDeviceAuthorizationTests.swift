import Foundation
import XCTest

@testable import Glance

final class GitHubDeviceAuthorizationTests: XCTestCase {
  private let configuration = GitHubOAuthConfiguration(
    clientID: "client-id", scopes: ["repo", "read:org"])
  private let fixedNow = Date(timeIntervalSince1970: 1_000)

  func testDeviceCodeRequestUsesConfiguredClientAndScopes() async throws {
    let transport = AuthorizationTransportStub(responses: [
      response(
        #"{"device_code":"device-secret","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
      )
    ])
    let service = makeService(transport: transport)

    let code = try await service.requestDeviceCode()

    XCTAssertEqual(code.userCode, "ABCD-EFGH")
    XCTAssertEqual(code.verificationURL.absoluteString, "https://github.com/login/device")
    XCTAssertEqual(code.expiresAt, fixedNow.addingTimeInterval(900))
    XCTAssertEqual(code.pollingInterval, 5)
    let recordedRequests = await transport.requests
    let request = try XCTUnwrap(recordedRequests.first)
    XCTAssertEqual(request.url?.absoluteString, "https://github.com/login/device/code")
    XCTAssertEqual(request.httpMethod, "POST")
    let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
    XCTAssertTrue(body?.contains("client_id=client-id") == true)
    XCTAssertTrue(body?.contains("scope=repo%20read:org") == true)
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
  }

  func testPendingAuthorizationPollsThenValidatesAuthenticatedUser() async throws {
    let transport = AuthorizationTransportStub(responses: [
      response(#"{"error":"authorization_pending"}"#),
      response(
        #"{"access_token":"test-access-token","expires_in":28800,"refresh_token":"test-refresh-token","refresh_token_expires_in":15897600,"scope":"repo,read:org","token_type":"bearer"}"#
      ),
      response(#"{"login":"octocat"}"#),
    ])
    let sleeper = AuthorizationSleeperStub()
    let service = makeService(transport: transport, sleeper: sleeper)

    let identity = try await service.waitForAuthorization(deviceCode: deviceCode())

    XCTAssertEqual(identity.login, "octocat")
    XCTAssertEqual(identity.credential.accessToken, "test-access-token")
    XCTAssertEqual(identity.credential.refreshToken, "test-refresh-token")
    XCTAssertEqual(identity.credential.expiresAt, fixedNow.addingTimeInterval(28_800))
    XCTAssertEqual(
      identity.credential.refreshTokenExpiresAt,
      fixedNow.addingTimeInterval(15_897_600))
    XCTAssertEqual(identity.grantedScopes, ["repo", "read:org"])
    let durations = await sleeper.durations
    XCTAssertEqual(durations, [5, 5])
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 3)
    XCTAssertEqual(requests[2].url?.absoluteString, "https://api.github.com/user")
    XCTAssertEqual(
      requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
  }

  func testSlowDownIncreasesTheNextPollingDelay() async throws {
    let transport = AuthorizationTransportStub(responses: [
      response(#"{"error":"slow_down"}"#),
      response(#"{"access_token":"token","scope":"repo"}"#),
      response(#"{"login":"octocat"}"#),
    ])
    let sleeper = AuthorizationSleeperStub()
    let service = makeService(transport: transport, sleeper: sleeper)

    _ = try await service.waitForAuthorization(deviceCode: deviceCode())

    let durations = await sleeper.durations
    XCTAssertEqual(durations, [5, 10])
  }

  func testAccessDeniedStopsAuthorization() async {
    let transport = AuthorizationTransportStub(responses: [
      response(#"{"error":"access_denied"}"#)
    ])
    let service = makeService(transport: transport)

    await assertThrowsDeviceError(.denied) {
      _ = try await service.waitForAuthorization(deviceCode: self.deviceCode())
    }
    let requestCount = await transport.requests.count
    XCTAssertEqual(requestCount, 1)
  }

  func testExpiredCodeDoesNotPoll() async {
    let transport = AuthorizationTransportStub(responses: [])
    let service = makeService(transport: transport)
    let expired = GitHubDeviceCode(
      deviceCode: "device", userCode: "CODE",
      verificationURL: URL(string: "https://github.com/login/device")!,
      expiresAt: fixedNow, pollingInterval: 5)

    await assertThrowsDeviceError(.expired) {
      _ = try await service.waitForAuthorization(deviceCode: expired)
    }
    let requestCount = await transport.requests.count
    XCTAssertEqual(requestCount, 0)
  }

  func testCodeExpiringDuringSleepDoesNotPoll() async {
    let transport = AuthorizationTransportStub(responses: [])
    let clock = SequenceClock(dates: [fixedNow, fixedNow, fixedNow.addingTimeInterval(5)])
    let service = GitHubDeviceAuthorizationService(
      configuration: configuration, transport: transport,
      sleeper: AuthorizationSleeperStub(), now: { clock.now() })
    let expiring = GitHubDeviceCode(
      deviceCode: "device", userCode: "CODE",
      verificationURL: URL(string: "https://github.com/login/device")!,
      expiresAt: fixedNow.addingTimeInterval(5), pollingInterval: 10)

    await assertThrowsDeviceError(.expired) {
      _ = try await service.waitForAuthorization(deviceCode: expiring)
    }
    let requestCount = await transport.requests.count
    XCTAssertEqual(requestCount, 0)
  }

  func testCancellationFromTransportIsNormalized() async {
    let service = GitHubDeviceAuthorizationService(
      configuration: configuration, transport: CancellingAuthorizationTransport())

    await assertThrowsDeviceError(.cancelled) {
      _ = try await service.requestDeviceCode()
    }
  }

  func testRefreshExchangesTokenValidatesIdentityAndPreservesNewExpiry() async throws {
    let transport = AuthorizationTransportStub(responses: [
      response(
        #"{"access_token":"new-access","expires_in":28800,"refresh_token":"new-refresh","refresh_token_expires_in":15897600,"scope":"repo,read:org"}"#
      ),
      response(#"{"login":"octocat"}"#),
    ])
    let service = makeService(transport: transport)
    let old = GitHubCredential(
      accessToken: "old-access", refreshToken: "old-refresh",
      expiresAt: fixedNow, refreshTokenExpiresAt: fixedNow.addingTimeInterval(100))

    let identity = try await service.refresh(credential: old)

    XCTAssertEqual(identity.login, "octocat")
    XCTAssertEqual(identity.credential.accessToken, "new-access")
    XCTAssertEqual(identity.credential.refreshToken, "new-refresh")
    XCTAssertEqual(identity.credential.expiresAt, fixedNow.addingTimeInterval(28_800))
    let requests = await transport.requests
    let body = String(data: try XCTUnwrap(requests.first?.httpBody), encoding: .utf8)
    XCTAssertTrue(body?.contains("grant_type=refresh_token") == true)
    XCTAssertTrue(body?.contains("refresh_token=old-refresh") == true)
  }

  private func makeService(
    transport: AuthorizationTransportStub,
    sleeper: AuthorizationSleeperStub = AuthorizationSleeperStub()
  ) -> GitHubDeviceAuthorizationService {
    let now = fixedNow
    return GitHubDeviceAuthorizationService(
      configuration: configuration, transport: transport, sleeper: sleeper, now: { now })
  }

  private func deviceCode() -> GitHubDeviceCode {
    GitHubDeviceCode(
      deviceCode: "device", userCode: "CODE",
      verificationURL: URL(string: "https://github.com/login/device")!,
      expiresAt: fixedNow.addingTimeInterval(900), pollingInterval: 5)
  }

  private func response(_ json: String, status: Int = 200) -> AuthorizationResponse {
    AuthorizationResponse(data: Data(json.utf8), status: status)
  }
}

final class KeychainCredentialStoreTests: XCTestCase {
  func testKeychainCredentialRoundTripAndDeletion() throws {
    let service = "app.glance.Glance.tests.\(UUID().uuidString)"
    let store = KeychainCredentialStore(service: service)
    let account = "github.com"
    defer { try? store.delete(account: account) }

    XCTAssertNil(try store.load(account: account))
    let expiry = Date(timeIntervalSince1970: 2_000)
    try store.save(
      GitHubCredential(
        accessToken: "first-token", refreshToken: "refresh-token", expiresAt: expiry),
      account: account)
    XCTAssertEqual(try store.load(account: account)?.accessToken, "first-token")
    XCTAssertEqual(try store.load(account: account)?.refreshToken, "refresh-token")
    XCTAssertEqual(try store.load(account: account)?.expiresAt, expiry)
    try store.save(GitHubCredential(accessToken: "replacement-token"), account: account)
    XCTAssertEqual(try store.load(account: account)?.accessToken, "replacement-token")
    try store.delete(account: account)
    XCTAssertNil(try store.load(account: account))
  }

  func testKeychainProviderReportsMissingCredential() async {
    let provider = KeychainCredentialProvider(
      store: InMemoryCredentialStore(credential: nil), account: "github.com")
    do {
      _ = try await provider.credential()
      XCTFail("Expected an authentication error")
    } catch let error as GitHubError {
      guard case .notAuthenticated = error else {
        return XCTFail("Expected notAuthenticated, got \(error)")
      }
    } catch {
      XCTFail("Expected GitHubError, got \(error)")
    }
  }

  func testOAuthProviderRefreshesAndPersistsExpiringCredential() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let store = MutableCredentialStore(
      credential: GitHubCredential(
        accessToken: "old", refreshToken: "refresh", expiresAt: now,
        refreshTokenExpiresAt: now.addingTimeInterval(1_000)))
    let transport = AuthorizationTransportStub(responses: [
      AuthorizationResponse(
        data: Data(
          #"{"access_token":"new","expires_in":28800,"refresh_token":"new-refresh","refresh_token_expires_in":15897600,"scope":"repo"}"#
            .utf8),
        status: 200),
      AuthorizationResponse(data: Data(#"{"login":"octocat"}"#.utf8), status: 200),
    ])
    let service = GitHubDeviceAuthorizationService(
      configuration: GitHubOAuthConfiguration(clientID: "client", scopes: ["repo"]),
      transport: transport, sleeper: AuthorizationSleeperStub(), now: { now })
    let provider = GitHubOAuthCredentialProvider(
      store: store, authorizationService: service, now: { now })

    let credential = try await provider.credential()

    XCTAssertEqual(credential.accessToken, "new")
    XCTAssertEqual(try store.load(account: "github.com")?.accessToken, "new")
  }

  func testOAuthProviderSerializesRefreshForConcurrentCallers() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let store = MutableCredentialStore(
      credential: GitHubCredential(
        accessToken: "old", refreshToken: "refresh", expiresAt: now,
        refreshTokenExpiresAt: now.addingTimeInterval(1_000)))
    let transport = AuthorizationTransportStub(responses: [
      AuthorizationResponse(
        data: Data(
          #"{"access_token":"new","expires_in":28800,"refresh_token":"new-refresh","refresh_token_expires_in":15897600,"scope":"repo"}"#
            .utf8),
        status: 200),
      AuthorizationResponse(data: Data(#"{"login":"octocat"}"#.utf8), status: 200),
    ])
    let service = GitHubDeviceAuthorizationService(
      configuration: GitHubOAuthConfiguration(clientID: "client", scopes: ["repo"]),
      transport: transport, sleeper: AuthorizationSleeperStub(), now: { now })
    let provider = GitHubOAuthCredentialProvider(
      store: store, authorizationService: service, now: { now })

    async let first = provider.credential()
    async let second = provider.credential()
    let credentials = try await [first, second]

    XCTAssertEqual(credentials.map(\.accessToken), ["new", "new"])
    let requestCount = await transport.requests.count
    XCTAssertEqual(requestCount, 2, "One token exchange and one identity validation are expected")
  }
}

private struct AuthorizationResponse: Sendable {
  let data: Data
  let status: Int
}

private actor AuthorizationTransportStub: GitHubAuthorizationTransport {
  private var responses: [AuthorizationResponse]
  private(set) var requests: [URLRequest] = []

  init(responses: [AuthorizationResponse]) { self.responses = responses }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    guard !responses.isEmpty else { throw GitHubDeviceAuthorizationError.invalidResponse }
    let next = responses.removeFirst()
    let response = HTTPURLResponse(
      url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
    return (next.data, response)
  }
}

private actor AuthorizationSleeperStub: GitHubAuthorizationSleeper {
  private(set) var durations: [TimeInterval] = []
  func sleep(for duration: TimeInterval) async throws { durations.append(duration) }
}

private struct CancellingAuthorizationTransport: GitHubAuthorizationTransport {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    throw CancellationError()
  }
}

private final class SequenceClock: @unchecked Sendable {
  private let lock = NSLock()
  private var dates: [Date]

  init(dates: [Date]) { self.dates = dates }

  func now() -> Date {
    lock.withLock {
      if dates.count == 1 { return dates[0] }
      return dates.removeFirst()
    }
  }
}

private struct InMemoryCredentialStore: CredentialSecureStore {
  let credential: GitHubCredential?
  func load(account: String) throws -> GitHubCredential? { credential }
  func save(_ credential: GitHubCredential, account: String) throws {}
  func delete(account: String) throws {}
}

private final class MutableCredentialStore: @unchecked Sendable, CredentialSecureStore {
  private let lock = NSLock()
  private var credential: GitHubCredential?

  init(credential: GitHubCredential?) { self.credential = credential }

  func load(account: String) throws -> GitHubCredential? {
    lock.withLock { credential }
  }

  func save(_ credential: GitHubCredential, account: String) throws {
    lock.withLock { self.credential = credential }
  }

  func delete(account: String) throws {
    lock.withLock { credential = nil }
  }
}

extension XCTestCase {
  fileprivate func assertThrowsDeviceError(
    _ expected: GitHubDeviceAuthorizationError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected)")
    } catch let error as GitHubDeviceAuthorizationError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected GitHubDeviceAuthorizationError, got \(error)")
    }
  }
}
