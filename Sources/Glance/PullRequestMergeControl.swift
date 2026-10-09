import SwiftUI

enum PullRequestMergeAction {
  case enableAutoMerge, disableAutoMerge, merge, markReadyForReview

  var requiresExpectedHead: Bool {
    switch self {
    case .enableAutoMerge, .merge: true
    case .disableAutoMerge, .markReadyForReview: false
    }
  }

  var progressHelp: String {
    switch self {
    case .enableAutoMerge: "Enabling auto-merge…"
    case .disableAutoMerge: "Disabling auto-merge…"
    case .merge: "Merging pull request…"
    case .markReadyForReview: "Marking ready for review…"
    }
  }
}

struct PullRequestMergeResult {
  let id: String
  let lifecycleState: PullRequest.LifecycleState
  let autoMergeEnabled: Bool
  var isDraft: Bool? = nil
}

/// GitHub's mergeability status is authoritative; aggregate checks cannot identify required checks.
struct PullRequestMergeControl {
  enum State { case open, autoMergeEnabled, ready, merged, closed, draft, unknown }

  let pullRequest: PullRequest

  var state: State {
    if pullRequest.lifecycleState == .merged { return .merged }
    if pullRequest.lifecycleState == .closed { return .closed }
    if pullRequest.isDraft { return .draft }
    guard pullRequest.lifecycleState == .open else { return .unknown }
    if pullRequest.isMergeable == true, pullRequest.mergeState == .clean,
      pullRequest.mergeQueuePosition == nil { return .ready }
    if pullRequest.autoMergeEnabled == true { return .autoMergeEnabled }
    return .open
  }

  var action: PullRequestMergeAction? {
    guard let capabilities = pullRequest.mergeCapabilities else { return nil }
    let hasMergeInputs = capabilities.preferredMethod != nil && pullRequest.headRefOID?.isEmpty == false
    // Lifecycle-only actions do not merge commits or require a merge method/head.
    switch state {
    case .autoMergeEnabled:
      return capabilities.viewerCanDisableAutoMerge == true ? .disableAutoMerge : nil
    case .draft:
      return pullRequest.lifecycleState == .open && capabilities.viewerCanMarkReadyForReview == true
        ? .markReadyForReview : nil
    case .ready:
      return hasMergeInputs && capabilities.viewerCanMerge ? .merge : nil
    case .open:
      return hasMergeInputs && capabilities.autoMergeAllowed && capabilities.viewerCanEnableAutoMerge
        && pullRequest.mergeQueuePosition == nil ? .enableAutoMerge : nil
    default: return nil
    }
  }

  var icon: Octicon {
    switch state {
    case .ready, .merged: .merged
    case .draft: .draft
    case .closed: .closed
    default: .pullRequest
    }
  }

  var color: Color {
    switch state {
    case .autoMergeEnabled, .ready: .statusGreen
    case .merged: .purple
    case .closed: .red
    default: .secondary
    }
  }

  var help: String {
    let method = pullRequest.mergeCapabilities?.preferredMethod?.rawValue ?? "merge"
    switch state {
    case .merged: return "Merged"
    case .closed: return "Closed pull request"
    case .draft:
      return action == .markReadyForReview ? "Mark ready for review" : "Draft pull request · ready-for-review permission unavailable"
    case .unknown: return "Refresh to load merge availability"
    case .autoMergeEnabled:
      return action == .disableAutoMerge ? "Disable auto-merge" : "Auto-merge enabled · disable permission unavailable"
    case .ready:
      return action == .merge ? "Merge pull request (\(method))" : "Ready to merge · merge permission unavailable"
    case .open:
      if pullRequest.mergeQueuePosition != nil { return "Pull request is in the merge queue" }
      guard let capabilities = pullRequest.mergeCapabilities else {
        return "Refresh to load merge availability"
      }
      if !capabilities.autoMergeAllowed { return "Auto-merge disabled in this repo" }
      return action == .enableAutoMerge ? "Enable auto-merge (\(method))" : "Auto-merge unavailable for this pull request"
    }
  }
}
