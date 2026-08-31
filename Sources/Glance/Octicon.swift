import AppKit
import SwiftUI

enum Octicon: String, CaseIterable {
  case pullRequest = "git-pull-request-16"
  case draft = "git-pull-request-draft-16"
  case stack = "stack-16"
  case approved = "check-circle-fill-16"
  case changesRequested = "x-circle-fill-16"
  case reviewPending = "dot-fill-16"
  case checksPassed = "check-circle-16"
  case checksFailed = "x-circle-16"
  case checksRunning = "clock-16"

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
    case .draft: "Draft"
    case .stack: "Stacked pull request"
    case .approved: "Approved"
    case .changesRequested: "Changes requested"
    case .reviewPending: "Review pending"
    case .checksPassed: "Checks passed"
    case .checksFailed: "Checks failed"
    case .checksRunning: "Checks running"
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
