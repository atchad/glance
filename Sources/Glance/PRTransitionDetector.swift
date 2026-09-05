import Foundation

struct PRTransition: Identifiable, Equatable {
  let id: String
  let pullRequest: PullRequest
  let event: PRNotificationEvent
  let message: String

  static func detect(
    previous: [PullRequest], current: [PullRequest],
    enabledEvents: Set<PRNotificationEvent> = Set(PRNotificationEvent.allCases)
  ) -> [PRTransition] {
    // Sections can overlap. Compare each PR once, including callers outside AppStore.
    let before = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var seen: Set<String> = []
    var output: [PRTransition] = []
    for pullRequest in current where seen.insert(pullRequest.id).inserted {
      guard !pullRequest.isDraft, pullRequest.lifecycleState != .closed,
        pullRequest.lifecycleState != .merged else { continue }
      let old = before[pullRequest.id]
      var candidates: [(PRNotificationEvent, String)] = []
      let personalRequest = pullRequest.viewerDidAuthor != true
        && pullRequest.viewerReviewRequested == true
      let requestDate = pullRequest.personalReviewRequestedAt
      let newerRequest = requestDate.map { date in
        old?.personalReviewRequestedAt.map { date > $0 } ?? false
      } ?? false
      let requestAfterReview = requestDate.map { date in
        pullRequest.viewerReviewSubmittedAt.map { date > $0 } ?? false
      } ?? false
      if personalRequest && (old?.viewerReviewRequested != true || newerRequest) {
        let repeated = requestAfterReview || (old?.viewerReviewRequested == true && newerRequest)
        candidates.append(repeated
          ? (.reviewRerequested, "Your review was requested again")
          : (.reviewRequested, "Review requested"))
      }
      if let old {
        if pullRequest.viewerDidAuthor != true, pullRequest.viewerReviewState != nil,
          let reviewedHead = pullRequest.viewerReviewedHeadOID,
          let head = pullRequest.headRefOID, reviewedHead != head, old.headRefOID != head
        {
          candidates.append((.commitsSinceReview, "New commits since your review"))
        }
        if pullRequest.viewerDidAuthor == true, pullRequest.reviewDecision == "CHANGES_REQUESTED",
          old.reviewDecision != "CHANGES_REQUESTED"
        {
          candidates.append((.changesRequested, "Changes requested"))
        }
        if pullRequest.mergeState == .conflicting, old.mergeState != .conflicting {
          candidates.append((.mergeConflict, "Merge conflict appeared"))
        }
        if pullRequest.checksState == .failure, old.checksState != .failure {
          let count = pullRequest.checks?.filter { $0.state == .failure }.count ?? 0
          candidates.append((.checksFailed, count > 1 ? "Fix \(count) failing checks" : "Fix failing checks"))
        }
        if isReady(pullRequest), !isReady(old) {
          candidates.append((.becameReady, "Ready to merge"))
        }
        if old.checksState == .failure, pullRequest.checksState == .success {
          candidates.append((.checksRecovered, "Checks recovered"))
        }
        if old.mergeQueuePosition != pullRequest.mergeQueuePosition {
          let message = pullRequest.mergeQueuePosition.map { "Merge queue · position \($0)" }
            ?? "Left merge queue"
          candidates.append((.mergeQueue, message))
        }
      }
      // Preserve one alert per PR per refresh, selecting the first enabled changed fact.
      // Priority: requests, commits, changes requested, conflict, failure, ready, recovery, queue.
      if let event = candidates.first(where: { enabledEvents.contains($0.0) }) {
        output.append(make(pullRequest, event.0, event.1))
      }
    }
    return output
  }

  private static func isReady(_ pullRequest: PullRequest) -> Bool {
    // Readiness is the product's composite state, including conversation/queue blockers.
    pullRequest.attention.reason == .readyToMerge
  }

  private static func make(
    _ pullRequest: PullRequest, _ event: PRNotificationEvent, _ message: String
  ) -> PRTransition {
    PRTransition(id: "\(pullRequest.id):\(event.rawValue)", pullRequest: pullRequest,
      event: event, message: message)
  }
}
