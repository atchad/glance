import AppKit
import SwiftUI

enum Octicon: String, CaseIterable {
  case pullRequest = "git-pull-request-16"
  case merged = "git-merge-16"
  case closed = "git-pull-request-closed-16"
  case draft = "git-pull-request-draft-16"
  case stack = "stack-16"
  case approved = "check-circle-fill-16"
  case changesRequested = "x-circle-fill-16"
  case reviewPending = "dot-fill-16"
  case checksPassed = "check-circle-16"
  case checksFailed = "x-circle-16"
  case checksRunning = "clock-16"
  case checksNeutral = "skip-16"
  case viewerApproved = "thumbsup-16"
  case viewerChangesRequested = "thumbsdown-16"
  case reviewRerequested = "sync-16"
  case newCommits = "git-commit-16"
  case mergeConflict = "alert-16"
  case conversations = "comment-discussion-16"
  case branchBehind = "git-branch-16"
  case reviewRequestUnknown = "question-16"
  case mergeQueue = "git-merge-queue-16"

  var image: NSImage {
    guard let url = Self.resourceBundle.url(forResource: rawValue, withExtension: "svg"),
      let image = NSImage(contentsOf: url)
    else {
      return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: name)!
    }
    image.isTemplate = true
    image.accessibilityDescription = name
    return image
  }

  private static let resourceBundle: Bundle = {
    if let resourceURL = Bundle.main.resourceURL,
      let appBundle = Bundle(url: resourceURL.appending(path: "Glance_Glance.bundle"))
    {
      return appBundle
    }
    return .module
  }()

  var name: String {
    switch self {
    case .pullRequest: "Pull requests"
    case .merged: "Merge pull request"
    case .closed: "Closed pull request"
    case .draft: "Draft"
    case .stack: "Stacked pull request"
    case .approved: "Approved"
    case .changesRequested: "Changes requested"
    case .reviewPending: "Review pending"
    case .checksPassed: "Checks passed"
    case .checksFailed: "Checks failed"
    case .checksRunning: "Checks running"
    case .checksNeutral: "Checks neutral"
    case .viewerApproved: "Approved by you"
    case .viewerChangesRequested: "Changes requested by you"
    case .reviewRerequested: "Review requested again"
    case .newCommits: "New commits"
    case .mergeConflict: "Merge conflicts"
    case .conversations: "Unresolved conversations"
    case .branchBehind: "Branch is behind"
    case .reviewRequestUnknown: "Review request status unavailable"
    case .mergeQueue: "Merge queue"
    }
  }
}

struct OcticonImage: View {
  let icon: Octicon
  var size: CGFloat = 14

  var body: some View {
    Image(nsImage: icon.image)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .accessibilityLabel(icon.name)
  }
}
