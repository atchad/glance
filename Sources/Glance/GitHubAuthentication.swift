import Foundation

struct GitHubCredential: Sendable, Equatable {
  let accessToken: String
}

protocol GitHubCredentialProvider: Sendable {
  func credential() async throws -> GitHubCredential
}

struct GitHubHost: Sendable, Equatable {
  let webURL: URL
  let apiURL: URL
  let graphQLURL: URL

  static let githubDotCom = GitHubHost(
    webURL: URL(string: "https://github.com")!,
    apiURL: URL(string: "https://api.github.com")!,
    graphQLURL: URL(string: "https://api.github.com/graphql")!)
}

struct GitHubSession: Sendable {
  let host: GitHubHost
  private let credentialProvider: any GitHubCredentialProvider

  init(
    host: GitHubHost = .githubDotCom,
    credentialProvider: any GitHubCredentialProvider = GitHubCLICredentialProvider()
  ) {
    self.host = host
    self.credentialProvider = credentialProvider
  }

  func credential() async throws -> GitHubCredential {
    try await credentialProvider.credential()
  }
}

struct GitHubCLICredentialProvider: GitHubCredentialProvider {
  private let executableCandidates: [String]

  init(
    executableCandidates: [String] = [
      "/opt/homebrew/bin/gh",
      "/usr/local/bin/gh",
      "/usr/bin/gh",
    ]
  ) {
    self.executableCandidates = executableCandidates
  }

  func credential() async throws -> GitHubCredential {
    let candidates = executableCandidates
    return try await Task.detached(priority: .userInitiated) {
      let process = Process()
      let output = Pipe()
      let errors = Pipe()
      guard
        let executable = candidates.first(where: {
          FileManager.default.isExecutableFile(atPath: $0)
        })
      else {
        throw GitHubError.ghUnavailable
      }
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = ["auth", "token"]
      process.standardOutput = output
      process.standardError = errors
      do { try process.run() } catch { throw GitHubError.ghUnavailable }
      process.waitUntilExit()
      let token =
        String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let detail =
        String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard process.terminationStatus == 0, !token.isEmpty else {
        throw GitHubError.notAuthenticated(detail)
      }
      return GitHubCredential(accessToken: token)
    }.value
  }
}

struct GitHubRequestFactory: Sendable {
  let host: GitHubHost
  var userAgent = "Glance/0.1"

  func restRequest(
    path: String,
    queryItems: [URLQueryItem] = [],
    credential: GitHubCredential
  ) throws -> URLRequest {
    let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
    var components = URLComponents(
      url: host.apiURL.appending(path: relativePath), resolvingAgainstBaseURL: false)
    components?.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components?.url else { throw GitHubError.invalidResponse }
    var request = URLRequest(url: url)
    applyCommonHeaders(to: &request, credential: credential)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    return request
  }

  func graphQLRequest(body: Data, credential: GitHubCredential) -> URLRequest {
    var request = URLRequest(url: host.graphQLURL)
    request.httpMethod = "POST"
    request.httpBody = body
    applyCommonHeaders(to: &request, credential: credential)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
  }

  private func applyCommonHeaders(
    to request: inout URLRequest,
    credential: GitHubCredential
  ) {
    request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
  }
}
