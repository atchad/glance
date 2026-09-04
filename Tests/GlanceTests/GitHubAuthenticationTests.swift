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
