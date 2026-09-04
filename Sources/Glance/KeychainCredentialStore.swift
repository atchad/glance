import Foundation
import Security

enum KeychainCredentialError: LocalizedError, Equatable {
  case unexpectedData
  case operationFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .unexpectedData:
      "Glance found an unreadable GitHub credential in Keychain."
    case .operationFailed(let status):
      SecCopyErrorMessageString(status, nil) as String?
        ?? "Keychain returned error \(status)."
    }
  }
}

protocol CredentialSecureStore: Sendable {
  func load(account: String) throws -> GitHubCredential?
  func save(_ credential: GitHubCredential, account: String) throws
  func delete(account: String) throws
}

struct KeychainCredentialStore: CredentialSecureStore {
  let service: String

  init(service: String = "app.glance.Glance.github-oauth") { self.service = service }

  func load(account: String) throws -> GitHubCredential? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainCredentialError.operationFailed(status) }
    guard let data = result as? Data else { throw KeychainCredentialError.unexpectedData }
    if let credential = try? JSONDecoder.githubCredential.decode(GitHubCredential.self, from: data)
    {
      return credential
    }
    guard let token = String(data: data, encoding: .utf8), !token.isEmpty else {
      throw KeychainCredentialError.unexpectedData
    }
    return GitHubCredential(accessToken: token)
  }

  func save(_ credential: GitHubCredential, account: String) throws {
    let token: Data
    do { token = try JSONEncoder.githubCredential.encode(credential) } catch {
      throw KeychainCredentialError.unexpectedData
    }
    let query = baseQuery(account: account)
    let attributes = [kSecValueData as String: token]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw KeychainCredentialError.operationFailed(updateStatus)
    }
    var item = query
    item[kSecValueData as String] = token
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(item as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw KeychainCredentialError.operationFailed(addStatus)
    }
  }

  func delete(account: String) throws {
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainCredentialError.operationFailed(status)
    }
  }

  private func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

extension JSONEncoder {
  fileprivate static var githubCredential: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var githubCredential: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

struct KeychainCredentialProvider: GitHubCredentialProvider {
  let store: any CredentialSecureStore
  let account: String

  init(
    store: any CredentialSecureStore = KeychainCredentialStore(),
    account: String = "github.com"
  ) {
    self.store = store
    self.account = account
  }

  func credential() async throws -> GitHubCredential {
    guard let credential = try store.load(account: account) else {
      throw GitHubError.notAuthenticated("Connect Glance to GitHub in Settings.")
    }
    return credential
  }
}

actor GitHubOAuthCredentialProvider: GitHubCredentialProvider {
  let store: any CredentialSecureStore
  let account: String
  let authorizationService: GitHubDeviceAuthorizationService
  let now: @Sendable () -> Date
  private var refreshTask: Task<GitHubCredential, Error>?

  init(
    store: any CredentialSecureStore = KeychainCredentialStore(),
    account: String = "github.com",
    authorizationService: GitHubDeviceAuthorizationService,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.store = store
    self.account = account
    self.authorizationService = authorizationService
    self.now = now
  }

  func credential() async throws -> GitHubCredential {
    guard let credential = try store.load(account: account) else {
      throw GitHubError.notAuthenticated("Connect Glance to GitHub in Settings.")
    }
    guard credential.needsRefresh(at: now()) else { return credential }
    if let refreshTask { return try await refreshTask.value }
    let store = store
    let account = account
    let service = authorizationService
    let task = Task {
      let identity = try await service.refresh(credential: credential)
      try store.save(identity.credential, account: account)
      return identity.credential
    }
    refreshTask = task
    do {
      let updated = try await task.value
      refreshTask = nil
      return updated
    } catch {
      refreshTask = nil
      throw error
    }
  }
}
