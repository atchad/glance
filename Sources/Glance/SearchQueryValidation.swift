import Foundation

struct SearchQueryValidation {
  enum State: Equatable {
    case idle, validating, valid, invalid(String)
  }

  private(set) var state: State = .idle
  private var requestID = UUID()

  mutating func reset() {
    requestID = UUID()
    state = .idle
  }

  mutating func begin() -> UUID {
    requestID = UUID()
    state = .validating
    return requestID
  }

  @discardableResult
  mutating func finish(_ request: UUID, error: String?) -> Bool {
    guard request == requestID else { return false }
    state = error.map(State.invalid) ?? .valid
    return error == nil
  }
}
