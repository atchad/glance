import Foundation
import XCTest
@testable import Glance

final class RequestConcurrencyTests: XCTestCase {
  func testSectionFanoutIsBoundedAndOrderPreserved() async throws {
    ConcurrencyProtocol.reset()
    let client = client()
    let sections = (0..<12).map { PRSection(name: "Section \($0)", query: "is:pr") }
    let result = try await client.fetchAll(sections: sections)
    let measured = ConcurrencyProtocol.measurements()
    print("SECTION_REQUESTS total=\(measured.total) peak=\(measured.peak)")
    XCTAssertEqual(result.snapshots.map(\.id), sections.map(\.id))
    XCTAssertEqual(measured.total, 12)
    XCTAssertLessThanOrEqual(measured.peak, 4)
  }

  func testCancellationDoesNotLaunchRemainingSections() async throws {
    ConcurrencyProtocol.reset()
    let client = client()
    let task = Task { try await client.fetchAll(sections: (0..<12).map {
      PRSection(name: "Section \($0)", query: "is:pr")
    }) }
    let deadline = ContinuousClock.now + .seconds(2)
    while ConcurrencyProtocol.measurements().total == 0, ContinuousClock.now < deadline {
      await Task.yield()
    }
    XCTAssertGreaterThan(ConcurrencyProtocol.measurements().total, 0)
    task.cancel()
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch { }
    XCTAssertLessThanOrEqual(ConcurrencyProtocol.measurements().total, 4)
  }

  private func client() -> GitHubClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ConcurrencyProtocol.self]
    return GitHubClient(session: GitHubSession(credentialProvider: ConcurrencyCredentials()),
      urlSession: URLSession(configuration: config))
  }
}

private struct ConcurrencyCredentials: GitHubCredentialProvider {
  func credential() async throws -> GitHubCredential { .init(accessToken: "fixture") }
}

private final class ConcurrencyProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  private static var active = 0
  private static var peak = 0
  private static var total = 0
  private var pending = false
  static func reset() { lock.withLock { active = 0; peak = 0; total = 0 } }
  static func measurements() -> (total: Int, peak: Int) { lock.withLock { (total, peak) } }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.lock.withLock {
      pending = true; Self.active += 1; Self.total += 1
      Self.peak = max(Self.peak, Self.active)
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [self] in
      let shouldDeliver = Self.lock.withLock {
        guard pending else { return false }
        pending = false; Self.active -= 1
        return true
      }
      guard shouldDeliver else { return }
      let data = Data(#"{"data":{"viewer":{"login":"fixture"},"search":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}"#.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
          httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() {
    Self.lock.withLock {
      if pending { pending = false; Self.active -= 1 }
    }
  }
}
