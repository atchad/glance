import Darwin
import Foundation
import XCTest

@testable import Glance

final class GitHubAuthenticationTests: XCTestCase {
  func testDefaultHostUsesGitHubDotComEndpoints() {
    XCTAssertEqual(GitHubHost.githubDotCom.webURL.absoluteString, "https://github.com")
    XCTAssertEqual(GitHubHost.githubDotCom.apiURL.absoluteString, "https://api.github.com")
    XCTAssertEqual(
      GitHubHost.githubDotCom.graphQLURL.absoluteString, "https://api.github.com/graphql")
  }

  func testSessionObtainsCredentialFromInjectedProvider() async throws {
    let session = GitHubSession(credentialProvider: StubCredentialProvider(token: "test-token"))

    let credential = try await session.credential()

    XCTAssertEqual(credential, GitHubCredential(accessToken: "test-token"))
  }

  func testRESTRequestUsesHostCredentialAndGitHubHeaders() throws {
    let factory = GitHubRequestFactory(host: .githubDotCom)

    let request = try factory.restRequest(
      path: "/search/issues",
      queryItems: [URLQueryItem(name: "q", value: "is:pr author:@me")],
      credential: GitHubCredential(accessToken: "secret"))

    XCTAssertEqual(request.url?.host, "api.github.com")
    XCTAssertEqual(request.url?.path, "/search/issues")
    XCTAssertEqual(
      URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "q" })?.value,
      "is:pr author:@me")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Glance/0.1")
  }

  func testGraphQLRequestUsesConfiguredEndpointAndBody() {
    let factory = GitHubRequestFactory(host: .githubDotCom)
    let body = Data("payload".utf8)

    let request = factory.graphQLRequest(
      body: body, credential: GitHubCredential(accessToken: "secret"))

    XCTAssertEqual(request.url, GitHubHost.githubDotCom.graphQLURL)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.httpBody, body)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Glance/0.1")
  }

  func testCLIProviderExplicitlyRequestsGitHubDotComToken() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("gh")
    try """
      #!/bin/sh
      [ "$#" -eq 4 ] && [ "$1" = auth ] && [ "$2" = token ] && \
      [ "$3" = --hostname ] && [ "$4" = github.com ] || exit 1
      printf 'github-dot-com-test-token\\n'
      """.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let provider = GitHubCLICredentialProvider(executableCandidates: [executable.path])
    let credential = try await provider.credential()

    XCTAssertEqual(credential.accessToken, "github-dot-com-test-token")
  }

  func testCLIProviderDrainsLargeOutputAndErrorStreams() async throws {
    let credential = try await runFakeCLI("""
      /usr/bin/awk 'BEGIN { for (i = 0; i < 200000; i++) printf "x" }'
      /usr/bin/awk 'BEGIN { for (i = 0; i < 200000; i++) printf "y" }' >&2
      """)
    XCTAssertEqual(credential.accessToken, String(repeating: "x", count: 200000))
  }

  func testCLIProviderRejectsExcessiveOutput() async throws {
    do {
      _ = try await runFakeCLI("/usr/bin/awk 'BEGIN { for (i = 0; i < 1100000; i++) printf \"x\" }'")
      XCTFail("Expected output limit")
    } catch let GitHubError.api(message) {
      XCTAssertEqual(message, "GitHub CLI returned too much output.")
    }
  }

  func testCLIProviderReportsFailure() async throws {
    do {
      _ = try await runFakeCLI("printf 'Sign in first' >&2; exit 1")
      XCTFail("Expected authentication failure")
    } catch let GitHubError.notAuthenticated(detail) {
      XCTAssertEqual(detail, "Sign in first")
    }
  }

  func testCLIProviderTimesOut() async throws {
    let start = Date()
    let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: pidFile) }
    do {
      _ = try await runFakeCLI("echo $$ > '\(pidFile.path)'; exec /bin/sleep 30", timeout: 1)
      XCTFail("Expected timeout")
    } catch let GitHubError.api(message) {
      XCTAssertEqual(message, "GitHub CLI timed out. Try refreshing again.")
    }
    XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    try assertProcessExited(pidFile)
  }

  func testCLIProviderCancelsRunningProcess() async throws {
    let start = Date()
    let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: pidFile) }
    let task = Task {
      try await self.runFakeCLI("echo $$ > '\(pidFile.path)'; exec /bin/sleep 30")
    }
    while !FileManager.default.fileExists(atPath: pidFile.path)
      && Date().timeIntervalSince(start) < 5
    {
      try await Task.sleep(for: .milliseconds(10))
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {}
    XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    try assertProcessExited(pidFile)
  }

  private func assertProcessExited(_ pidFile: URL) throws {
    let value = try String(contentsOf: pidFile, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let pid = try XCTUnwrap(Int32(value))
    XCTAssertEqual(kill(pid, 0), -1)
    XCTAssertEqual(errno, ESRCH)
  }

  private func runFakeCLI(_ script: String, timeout: TimeInterval = 30) async throws
    -> GitHubCredential
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("gh")
    try ("#!/bin/sh\n" + script).write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    return try await GitHubCLICredentialProvider(
      executableCandidates: [executable.path], timeout: timeout).credential()
  }

  func testCLIProviderReportsUnavailableWhenNoCandidateExists() async {
    let provider = GitHubCLICredentialProvider(executableCandidates: ["/missing/gh"])

    do {
      _ = try await provider.credential()
      XCTFail("Expected an unavailable GitHub CLI error")
    } catch let error as GitHubError {
      guard case .ghUnavailable = error else {
        return XCTFail("Expected ghUnavailable, got \(error)")
      }
    } catch {
      XCTFail("Expected GitHubError, got \(error)")
    }
  }
}

private struct StubCredentialProvider: GitHubCredentialProvider {
  let token: String

  func credential() async throws -> GitHubCredential {
    GitHubCredential(accessToken: token)
  }
}
