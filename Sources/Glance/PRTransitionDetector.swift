import Foundation

struct PRTransition: Identifiable, Equatable {
  let id: String
  let pullRequest: PullRequest
  let event: PRNotificationEvent
  let message: String

  static func detect(previous: [PullRequest], current: [PullRequest]) -> [PRTransition] {
    let before = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
    var output: [PRTransition] = []
    for pullRequest in current {
      guard let old = before[pullRequest.id] else {
        if pullRequest.attention.reason == .reviewRequested {
          output.append(make(pullRequest, .reviewRequested, "Review requested"))
        }
        continue
      }
      let oldReason = old.attention.reason
      let reason = pullRequest.attention.reason
      let event: (PRNotificationEvent, String)? = switch reason {
      case .reviewRerequested where oldReason != reason: (.reviewRerequested, "Your review was requested again")
      case .commitsSinceReview where old.headRefOID != pullRequest.headRefOID: (.commitsSinceReview, "New commits since your review")
      case .changesRequested where oldReason != reason: (.changesRequested, "Changes requested")
      case .checksFailing where old.checksState != .failure: (.checksFailed, pullRequest.attention.message)
      case .readyToMerge where oldReason != reason: (.becameReady, "Ready to merge")
      case .mergeConflict where oldReason != reason: (.mergeConflict, "Merge conflict appeared")
      default:
        if old.checksState == .failure && pullRequest.checksState == .success {
          (.checksRecovered, "Checks recovered")
        } else if old.mergeQueuePosition != pullRequest.mergeQueuePosition,
          old.mergeQueuePosition != nil || pullRequest.mergeQueuePosition != nil
        {
          (.mergeQueue, pullRequest.attention.message)
        } else { nil }
      }
      if let event { output.append(make(pullRequest, event.0, event.1)) }
    }
    return output
  }

  private static func make(
    _ pullRequest: PullRequest, _ event: PRNotificationEvent, _ message: String
  ) -> PRTransition {
    PRTransition(id: "\(pullRequest.id):\(event.rawValue)", pullRequest: pullRequest,
      event: event, message: message)
  }
}
