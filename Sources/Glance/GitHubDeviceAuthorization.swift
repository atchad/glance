import Foundation

struct GitHubOAuthConfiguration: Sendable, Equatable {
  let clientID: String
  let scopes: [String]

  static func bundled(in bundle: Bundle = .main) throws -> GitHubOAuthConfiguration {
    guard
      let value = bundle.object(forInfoDictionaryKey: "GlanceGitHubOAuthClientID") as? String,
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw GitHubDeviceAuthorizationError.missingClientID
    }
    return GitHubOAuthConfiguration(clientID: value, scopes: ["repo", "read:org"])
  }
}

struct GitHubDeviceCode: Sendable, Equatable {
  let deviceCode: String
  let userCode: String
  let verificationURL: URL
  let expiresAt: Date
  let pollingInterval: TimeInterval
}

struct GitHubAuthorizedIdentity: Sendable, Equatable {
  let login: String
  let credential: GitHubCredential
  let grantedScopes: Set<String>
}

enum GitHubDeviceAuthorizationError: LocalizedError, Equatable {
  case missingClientID
  case invalidResponse
  case requestFailed(String)
  case expired
  case denied
  case cancelled

  var errorDescription: String? {
    switch self {
    case .missingClientID:
      "This build of Glance is not configured for direct GitHub sign-in."
    case .invalidResponse:
      "GitHub returned an unreadable sign-in response."
    case .requestFailed(let message):
      message
    case .expired:
      "The GitHub sign-in code expired. Start sign-in again to get a new code."
    case .denied:
      "GitHub sign-in was cancelled in the browser."
    case .cancelled:
      "GitHub sign-in was cancelled."
    }
  }
}

protocol GitHubAuthorizationTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionAuthorizationTransport: GitHubAuthorizationTransport {
  let session: URLSession

  init(session: URLSession = .shared) { self.session = session }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw GitHubDeviceAuthorizationError.invalidResponse
    }
    return (data, http)
  }
}

protocol GitHubAuthorizationSleeper: Sendable {
  func sleep(for duration: TimeInterval) async throws
}

struct ContinuousClockAuthorizationSleeper: GitHubAuthorizationSleeper {
  func sleep(for duration: TimeInterval) async throws {
    try await Task.sleep(for: .seconds(duration))
  }
}

struct GitHubDeviceAuthorizationService: Sendable {
  private let host: GitHubHost
  private let configuration: GitHubOAuthConfiguration
  private let transport: any GitHubAuthorizationTransport
  private let sleeper: any GitHubAuthorizationSleeper
  private let now: @Sendable () -> Date

  init(
    host: GitHubHost = .githubDotCom,
    configuration: GitHubOAuthConfiguration,
    transport: any GitHubAuthorizationTransport = URLSessionAuthorizationTransport(),
    sleeper: any GitHubAuthorizationSleeper = ContinuousClockAuthorizationSleeper(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.host = host
    self.configuration = configuration
    self.transport = transport
    self.sleeper = sleeper
    self.now = now
  }

  func requestDeviceCode() async throws -> GitHubDeviceCode {
    let url = host.webURL.appending(path: "login/device/code")
    let body = formBody([
      URLQueryItem(name: "client_id", value: configuration.clientID),
      URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
    ])
    let (data, response) = try await authorizationData(
      for: postRequest(url: url, body: body))
    guard (200..<300).contains(response.statusCode) else {
      throw GitHubDeviceAuthorizationError.requestFailed("GitHub could not start sign-in.")
    }
    let payload = try decode(DeviceCodeResponse.self, from: data)
    guard let verificationURL = URL(string: payload.verificationURI), payload.expiresIn > 0,
      payload.interval > 0
    else { throw GitHubDeviceAuthorizationError.invalidResponse }
    return GitHubDeviceCode(
      deviceCode: payload.deviceCode,
      userCode: payload.userCode,
      verificationURL: verificationURL,
      expiresAt: now().addingTimeInterval(TimeInterval(payload.expiresIn)),
      pollingInterval: TimeInterval(payload.interval))
  }

  func waitForAuthorization(deviceCode: GitHubDeviceCode) async throws -> GitHubAuthorizedIdentity {
    var interval = deviceCode.pollingInterval
    while now() < deviceCode.expiresAt {
      let remaining = deviceCode.expiresAt.timeIntervalSince(now())
      do {
        try await sleeper.sleep(for: min(interval, remaining))
        try Task.checkCancellation()
      } catch is CancellationError {
        throw GitHubDeviceAuthorizationError.cancelled
      }
      guard now() < deviceCode.expiresAt else {
        throw GitHubDeviceAuthorizationError.expired
      }
      let result = try await poll(deviceCode: deviceCode.deviceCode)
      switch result {
      case .pending:
        continue
      case .slowDown(let serverInterval):
        interval = max(interval + 5, serverInterval ?? 0)
      case .authorized(let credential, let scopes):
        return try await validate(credential: credential, grantedScopes: scopes)
      case .expired:
        throw GitHubDeviceAuthorizationError.expired
      case .denied:
        throw GitHubDeviceAuthorizationError.denied
      }
    }
    throw GitHubDeviceAuthorizationError.expired
  }

  func refresh(credential: GitHubCredential) async throws -> GitHubAuthorizedIdentity {
    guard let refreshToken = credential.refreshToken else {
      throw GitHubDeviceAuthorizationError.requestFailed(
        "GitHub sign-in expired. Connect Glance to GitHub again.")
    }
    if let refreshExpiry = credential.refreshTokenExpiresAt, refreshExpiry <= now() {
      throw GitHubDeviceAuthorizationError.requestFailed(
        "GitHub sign-in expired. Connect Glance to GitHub again.")
    }
    let url = host.webURL.appending(path: "login/oauth/access_token")
    let body = formBody([
      URLQueryItem(name: "client_id", value: configuration.clientID),
      URLQueryItem(name: "grant_type", value: "refresh_token"),
      URLQueryItem(name: "refresh_token", value: refreshToken),
    ])
    do {
      let (data, response) = try await authorizationData(
        for: postRequest(url: url, body: body))
      guard (200..<300).contains(response.statusCode) else {
        throw GitHubDeviceAuthorizationError.requestFailed("GitHub could not refresh sign-in.")
      }
      let payload = try decode(TokenResponse.self, from: data)
      guard payload.error == nil, let updated = payload.credential(now: now()) else {
        throw GitHubDeviceAuthorizationError.requestFailed(
          payload.errorDescription ?? "GitHub could not refresh sign-in.")
      }
      return try await validate(
        credential: updated,
        grantedScopes: payload.grantedScopes)
    } catch is CancellationError {
      throw GitHubDeviceAuthorizationError.cancelled
    }
  }

  private func poll(deviceCode: String) async throws -> PollResult {
    let url = host.webURL.appending(path: "login/oauth/access_token")
    let body = formBody([
      URLQueryItem(name: "client_id", value: configuration.clientID),
      URLQueryItem(name: "device_code", value: deviceCode),
      URLQueryItem(
        name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code"),
    ])
    let (data, response) = try await authorizationData(
      for: postRequest(url: url, body: body))
    guard (200..<300).contains(response.statusCode) else {
      throw GitHubDeviceAuthorizationError.requestFailed("GitHub could not complete sign-in.")
    }
    let payload = try decode(TokenResponse.self, from: data)
    if let credential = payload.credential(now: now()) {
      return .authorized(credential: credential, scopes: payload.grantedScopes)
    }
    switch payload.error {
    case "authorization_pending": return .pending
    case "slow_down": return .slowDown(payload.interval.map(TimeInterval.init))
    case "expired_token": return .expired
    case "access_denied": return .denied
    default:
      throw GitHubDeviceAuthorizationError.requestFailed(
        payload.errorDescription ?? "GitHub could not complete sign-in.")
    }
  }

  private func validate(
    credential: GitHubCredential,
    grantedScopes: Set<String>
  ) async throws -> GitHubAuthorizedIdentity {
    var request = URLRequest(url: host.apiURL.appending(path: "user"))
    request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Glance/0.1", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await authorizationData(for: request)
    guard (200..<300).contains(response.statusCode) else {
      throw GitHubDeviceAuthorizationError.requestFailed(
        "GitHub accepted the sign-in but could not verify the account.")
    }
    let user = try decode(AuthenticatedUser.self, from: data)
    return GitHubAuthorizedIdentity(
      login: user.login,
      credential: credential,
      grantedScopes: grantedScopes)
  }

  private func postRequest(url: URL, body: Data) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("Glance/0.1", forHTTPHeaderField: "User-Agent")
    return request
  }

  private func authorizationData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    do { return try await transport.data(for: request) } catch is CancellationError {
      throw GitHubDeviceAuthorizationError.cancelled
    }
  }

  private func formBody(_ items: [URLQueryItem]) -> Data {
    var components = URLComponents()
    components.queryItems = items
    return Data((components.percentEncodedQuery ?? "").utf8)
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do { return try JSONDecoder().decode(type, from: data) } catch {
      throw GitHubDeviceAuthorizationError.invalidResponse
    }
  }
}

private enum PollResult {
  case pending
  case slowDown(TimeInterval?)
  case authorized(credential: GitHubCredential, scopes: Set<String>)
  case expired
  case denied
}

private struct DeviceCodeResponse: Decodable {
  let deviceCode: String
  let userCode: String
  let verificationURI: String
  let expiresIn: Int
  let interval: Int

  private enum CodingKeys: String, CodingKey {
    case deviceCode = "device_code"
    case userCode = "user_code"
    case verificationURI = "verification_uri"
    case expiresIn = "expires_in"
    case interval
  }
}

private struct TokenResponse: Decodable {
  let accessToken: String?
  let scope: String?
  let error: String?
  let errorDescription: String?
  let interval: Int?
  let expiresIn: Int?
  let refreshToken: String?
  let refreshTokenExpiresIn: Int?

  private enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case scope, error, interval
    case expiresIn = "expires_in"
    case refreshToken = "refresh_token"
    case refreshTokenExpiresIn = "refresh_token_expires_in"
    case errorDescription = "error_description"
  }

  var grantedScopes: Set<String> {
    Set((scope ?? "").split(separator: ",").map(String.init))
  }

  func credential(now: Date) -> GitHubCredential? {
    guard let accessToken else { return nil }
    return GitHubCredential(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresIn.map { now.addingTimeInterval(TimeInterval($0)) },
      refreshTokenExpiresAt: refreshTokenExpiresIn.map {
        now.addingTimeInterval(TimeInterval($0))
      })
  }
}

private struct AuthenticatedUser: Decodable { let login: String }
