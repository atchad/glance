import AppKit
import SwiftUI

struct GitHubConnectionView: View {
  @ObservedObject var store: AppStore
  var compact = false
  @State private var confirmingDisconnect = false

  var body: some View {
    VStack(alignment: compact ? .center : .leading, spacing: compact ? 14 : 10) {
      switch store.githubConnectionState {
      case .connected(let login):
        connectedView(login: login)
      case .connecting:
        connectingView
      case .failed(let message):
        connectionActions(message: message)
      case .disconnected:
        connectionActions(message: nil)
      }
    }
    .confirmationDialog(
      "Disconnect GitHub?", isPresented: $confirmingDisconnect, titleVisibility: .visible
    ) {
      Button("Disconnect", role: .destructive) { store.disconnectGitHub() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Glance will remove its GitHub credential from Keychain. Saved pull requests remain available until you reconnect."
      )
    }
  }

  @ViewBuilder private func connectedView(login: String) -> some View {
    if compact {
      Label("Connected as @\(login)", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    } else {
      LabeledContent("GitHub account") {
        Label("@\(login)", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.primary, .green)
      }
      LabeledContent("Connected with", value: store.githubAuthenticationMethod.title)
      HStack {
        Button("Check Connection") { store.refresh() }
        if store.githubAuthenticationMethod == .direct {
          Button("Disconnect…", role: .destructive) { confirmingDisconnect = true }
          Button("Use GitHub CLI") { store.useGitHubCLI() }
        } else {
          Button("Connect Directly…") { store.connectDirectlyToGitHub() }
        }
      }
    }
  }

  @ViewBuilder private var connectingView: some View {
    if let code = store.githubDeviceCode {
      VStack(alignment: compact ? .center : .leading, spacing: 8) {
        Text("Enter this code on GitHub")
          .font(compact ? .callout : .headline)
        Text(code.userCode)
          .font(.system(.title2, design: .monospaced, weight: .semibold))
          .textSelection(.enabled)
          .accessibilityLabel("GitHub device code \(code.userCode)")
        Text(
          "The authorization page has opened in your browser. Glance will finish connecting automatically."
        )
        .font(.caption).foregroundStyle(.secondary)
        .multilineTextAlignment(compact ? .center : .leading)
        HStack {
          Button("Copy Code") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code.userCode, forType: .string)
          }
          Button("Open GitHub") { NSWorkspace.shared.open(code.verificationURL) }
          Button("Cancel", role: .cancel) { store.cancelGitHubSignIn() }
        }
      }
    } else {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Starting GitHub sign-in…")
      }
      Button("Cancel", role: .cancel) { store.cancelGitHubSignIn() }
    }
  }

  @ViewBuilder private func connectionActions(message: String?) -> some View {
    if let message {
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(.caption).foregroundStyle(.orange)
        .multilineTextAlignment(compact ? .center : .leading)
    }
    if !compact {
      Text(
        "Connect directly for the simplest setup. Glance stores your credential securely in Keychain."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    if compact {
      VStack(spacing: 8) { connectionButtons(message: message) }
    } else {
      HStack { connectionButtons(message: message) }
    }
    if !compact {
      Link("About GitHub CLI…", destination: URL(string: "https://cli.github.com/")!)
        .font(.caption)
    }
  }

  @ViewBuilder private func connectionButtons(message: String?) -> some View {
    Button(message == nil ? "Connect to GitHub" : "Try Direct Sign-In Again") {
      store.connectDirectlyToGitHub()
    }
    .buttonStyle(.borderedProminent)
    Button("Use GitHub CLI") { store.useGitHubCLI() }
  }
}
