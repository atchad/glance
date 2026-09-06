import Darwin
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
  private let timeout: TimeInterval

  init(
    executableCandidates: [String] = [
      "/opt/homebrew/bin/gh",
      "/usr/local/bin/gh",
      "/usr/bin/gh",
    ],
    timeout: TimeInterval = 30
  ) {
    self.executableCandidates = executableCandidates
    self.timeout = timeout
  }

  func credential() async throws -> GitHubCredential {
    let candidates = executableCandidates
    let timeout = timeout
    // Keep Process launch, polling, and cleanup on one thread; only the caller suspends.
    let task = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
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
      process.arguments = ["auth", "token", "--hostname", "github.com"]
      process.standardOutput = output
      process.standardError = errors
      do { try process.run() } catch { throw GitHubError.ghUnavailable }
      let handles = [output.fileHandleForReading, errors.fileHandleForReading]
      defer {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        for handle in handles { try? handle.close() }
      }
      for handle in handles {
        let flags = fcntl(handle.fileDescriptor, F_GETFL)
        guard flags != -1, fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
          throw GitHubError.ghUnavailable
        }
      }
      var captured = [Data(), Data()]
      var buffer = [UInt8](repeating: 0, count: 16_384)
      let deadline = ProcessInfo.processInfo.systemUptime + timeout
      while true {
        if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline {
          try Task.checkCancellation()
          throw GitHubError.api("GitHub CLI timed out. Try refreshing again.")
        }
        let running = process.isRunning
        var receivedData = false
        for (index, handle) in handles.enumerated() {
          let count = read(handle.fileDescriptor, &buffer, buffer.count)
          if count > 0 {
            guard captured[index].count + count <= 1_048_576 else {
              throw GitHubError.api("GitHub CLI returned too much output.")
            }
            captured[index].append(contentsOf: buffer.prefix(count))
            receivedData = true
          } else if count < 0 && errno != EAGAIN && errno != EINTR {
            throw GitHubError.ghUnavailable
          }
        }
        if !receivedData {
          if !running { break }
          usleep(10_000)
        }
      }
      try Task.checkCancellation()
      let token = String(data: captured[0], encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let detail = String(data: captured[1], encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard process.terminationStatus == 0, !token.isEmpty else {
        throw GitHubError.notAuthenticated(detail)
      }
      return GitHubCredential(accessToken: token)
    }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
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
