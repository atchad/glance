import Foundation
import XCTest

@testable import Glance

final class GitHubConnectionTests: XCTestCase {
  func testLegacyPreferencesKeepUsingGitHubCLI() throws {
    let preferences = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    XCTAssertEqual(preferences.githubAuthenticationMethod, .githubCLI)
  }

  func testAuthenticationMethodRoundTrips() throws {
    var preferences = Preferences.default
    preferences.githubAuthenticationMethod = .direct
    let decoded = try JSONDecoder().decode(
      Preferences.self, from: JSONEncoder().encode(preferences))
    XCTAssertEqual(decoded.githubAuthenticationMethod, .direct)
  }

  @MainActor
  func testDirectSignInPersistsCredentialAndSelectsDirectAuthentication() async throws {
    let store = ConnectionCredentialStore()
    let service = ConnectionAuthorizationStub()
    let openedURLs = ConnectionURLRecorder()
    let appStore = AppStore(
      credentialStore: store, initialPreferences: .default, persistsToDisk: false,
      refreshAfterAuthentication: false, openURL: { openedURLs.record($0) },
      authorizationServiceFactory: { service })

    appStore.connectDirectlyToGitHub()
    for _ in 0..<100 {
      if appStore.githubConnectionState == .connected(login: "octocat") { break }
      await Task.yield()
    }

    XCTAssertEqual(appStore.githubConnectionState, .connected(login: "octocat"))
    XCTAssertEqual(appStore.githubAuthenticationMethod, .direct)
    XCTAssertEqual(try store.load(account: "github.com")?.accessToken, "access-token")
    XCTAssertEqual(openedURLs.urls, [URL(string: "https://github.com/login/device")!])
  }

  @MainActor
  func testStaleAuthorizationCannotOverwriteRetryOrPersistCredential() async throws {
    let store = ConnectionCredentialStore()
    let first = ControlledConnectionAuthorizationStub(userCode: "FIRST")
    let second = ControlledConnectionAuthorizationStub(userCode: "SECOND")
    let services = ConnectionAuthorizationFactory(services: [first, second])
    let appStore = AppStore(
      credentialStore: store, initialPreferences: .default, persistsToDisk: false,
      refreshAfterAuthentication: false, openURL: { _ in },
      authorizationServiceFactory: { try services.next() })

    appStore.connectDirectlyToGitHub()
    await first.waitUntilPolling()
    appStore.connectDirectlyToGitHub()
    await second.waitUntilPolling()

    await first.complete(login: "stale", token: "stale-token")
    await Task.yield()
    XCTAssertEqual(appStore.githubConnectionState, .connecting)
    XCTAssertEqual(appStore.githubDeviceCode?.userCode, "SECOND")
    XCTAssertNil(try store.load(account: "github.com"))

    await second.complete(login: "current", token: "current-token")
    for _ in 0..<100 {
      if appStore.githubConnectionState == .connected(login: "current") { break }
      await Task.yield()
    }
    XCTAssertEqual(appStore.githubConnectionState, .connected(login: "current"))
    XCTAssertEqual(try store.load(account: "github.com")?.accessToken, "current-token")
  }

  @MainActor
  func testDisconnectDeletesOnlyDirectCredentialAndPreservesCachedPreferences() async throws {
    let store = ConnectionCredentialStore(
      credential: GitHubCredential(accessToken: "access-token"))
    var preferences = Preferences.default
    preferences.githubAuthenticationMethod = .direct
    preferences.pinnedPullRequests = ["PR_1"]
    let appStore = AppStore(
      credentialStore: store, initialPreferences: preferences, persistsToDisk: false,
      refreshAfterAuthentication: false, openURL: { _ in },
      authorizationServiceFactory: { ConnectionAuthorizationStub() })

    appStore.disconnectGitHub()

    XCTAssertNil(try store.load(account: "github.com"))
    XCTAssertEqual(appStore.githubAuthenticationMethod, .direct)
    XCTAssertEqual(appStore.githubConnectionState, .disconnected)
    XCTAssertEqual(appStore.preferences.pinnedPullRequests, ["PR_1"])
  }
}

private final class ConnectionURLRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recordedURLs: [URL] = []

  var urls: [URL] { lock.withLock { recordedURLs } }
  func record(_ url: URL) { lock.withLock { recordedURLs.append(url) } }
}

private final class ConnectionAuthorizationFactory: @unchecked Sendable {
  private let lock = NSLock()
  private var services: [any GitHubDeviceAuthorizing]

  init(services: [any GitHubDeviceAuthorizing]) { self.services = services }

  func next() throws -> any GitHubDeviceAuthorizing {
    try lock.withLock {
      guard !services.isEmpty else { throw GitHubDeviceAuthorizationError.cancelled }
      return services.removeFirst()
    }
  }
}

private actor ControlledConnectionAuthorizationStub: GitHubDeviceAuthorizing {
  private let userCode: String
  private var continuation: CheckedContinuation<GitHubAuthorizedIdentity, Error>?

  init(userCode: String) { self.userCode = userCode }

  func requestDeviceCode() async throws -> GitHubDeviceCode {
    GitHubDeviceCode(
      deviceCode: "device-\(userCode)", userCode: userCode,
      verificationURL: URL(string: "https://github.com/login/device")!,
      expiresAt: .distantFuture, pollingInterval: 5)
  }

  func waitForAuthorization(deviceCode: GitHubDeviceCode) async throws
    -> GitHubAuthorizedIdentity
  {
    try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func waitUntilPolling() async {
    while continuation == nil { await Task.yield() }
  }

  func complete(login: String, token: String) {
    continuation?.resume(
      returning: GitHubAuthorizedIdentity(
        login: login, credential: GitHubCredential(accessToken: token), grantedScopes: ["repo"]))
    continuation = nil
  }

  func refresh(credential: GitHubCredential) async throws -> GitHubAuthorizedIdentity {
    GitHubAuthorizedIdentity(login: "unused", credential: credential, grantedScopes: ["repo"])
  }
}

private final class ConnectionCredentialStore: @unchecked Sendable, CredentialSecureStore {
  private let lock = NSLock()
  private var credential: GitHubCredential?

  init(credential: GitHubCredential? = nil) { self.credential = credential }

  func load(account: String) throws -> GitHubCredential? { lock.withLock { credential } }
  func save(_ credential: GitHubCredential, account: String) throws {
    lock.withLock { self.credential = credential }
  }
  func delete(account: String) throws { lock.withLock { credential = nil } }
}

private struct ConnectionAuthorizationStub: GitHubDeviceAuthorizing {
  func requestDeviceCode() async throws -> GitHubDeviceCode {
    GitHubDeviceCode(
      deviceCode: "device-secret", userCode: "ABCD-EFGH",
      verificationURL: URL(string: "https://github.com/login/device")!,
      expiresAt: .distantFuture, pollingInterval: 5)
  }

  func waitForAuthorization(deviceCode: GitHubDeviceCode) async throws
    -> GitHubAuthorizedIdentity
  {
    GitHubAuthorizedIdentity(
      login: "octocat", credential: GitHubCredential(accessToken: "access-token"),
      grantedScopes: ["repo", "read:org"])
  }

  func refresh(credential: GitHubCredential) async throws -> GitHubAuthorizedIdentity {
    GitHubAuthorizedIdentity(login: "octocat", credential: credential, grantedScopes: ["repo"])
  }
}
