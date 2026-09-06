import AppKit
import SwiftUI

/// Factual presentation of the fetched contexts; this does not infer required checks.
struct PullRequestDetailsView: View {
  let pullRequest: PullRequest
  let checksAreCached: Bool
  let close: () -> Void
  @Environment(\.openURL) private var openURL
  @State private var copyFocusRequest = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Pull request details").font(.headline)
        Spacer()
        Button("Done", action: close)
          .keyboardShortcut(.cancelAction)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Text(verbatim: "\(pullRequest.repository) #\(pullRequest.number)")
            .font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
          Text(verbatim: pullRequest.title)
            .font(.body).fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
          Divider()
          Text("Fetched checks").font(.headline)
          if checksAreCached {
            Label("Cached data · may be out of date", systemImage: "clock")
              .font(.caption).foregroundStyle(.secondary)
          }
          Text("More checks may exist on GitHub. This list does not identify required checks.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if let checks = pullRequest.checks {
            if checks.isEmpty {
              Text("No checks were fetched.").foregroundStyle(.secondary)
            }
            ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
              VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: check.name.isEmpty ? "Unnamed check" : check.name)
                  .fixedSize(horizontal: false, vertical: true)
                  .textSelection(.enabled)
                HStack {
                  Label(check.state.detailLabel, systemImage: check.state.detailSymbol)
                    .foregroundStyle(check.state.detailColor)
                  Spacer()
                  if let url = check.detailsURL {
                    Button("Open check") { openURL(url) }
                      .accessibilityLabel("Open check: \(check.name)")
                  } else {
                    Text("No link available").foregroundStyle(.secondary)
                  }
                }
                .font(.caption)
              }
              .padding(.vertical, 4)
            }
          } else {
            Text("Check details are unavailable.").foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: 340)
      DetailActionButton(label: "Copy title", title: "Copy title", focusRequest: copyFocusRequest) {
        Self.copyTitle(pullRequest.title, to: .general)
      }
      .frame(width: 90, height: 24)
    }
    .padding(16)
    .frame(width: 330)
    .onAppear { copyFocusRequest += 1 }
    .onExitCommand(perform: close)
  }

  static func copyTitle(_ title: String, to pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    pasteboard.setString(title, forType: .string)
  }
}

extension PullRequest.CheckState {
  var detailLabel: String {
    switch self {
    case .success: "Passed"
    case .failure: "Failed"
    case .pending: "Pending"
    case .neutral: "Neutral"
    case .unknown: "Unknown"
    }
  }

  var detailSymbol: String {
    switch self {
    case .success: "checkmark.circle"
    case .failure: "xmark.circle"
    case .pending: "clock"
    case .neutral: "minus.circle"
    case .unknown: "questionmark.circle"
    }
  }

  var detailColor: Color {
    switch self {
    case .success: .statusGreen
    case .failure: .red
    case .pending: .orange
    case .neutral, .unknown: .secondary
    }
  }
}
