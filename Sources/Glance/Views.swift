import AppKit
import SwiftUI

enum DashboardSurface { case menuBar, panel }

struct DashboardView: View {
  @ObservedObject var store: AppStore
  var surface: DashboardSurface
  var togglePanel: (() -> Void)?
  var openSettings: (() -> Void)?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if store.errorMessage != nil, store.snapshots.isEmpty {
        if store.connectionIssue == .authentication {
          GitHubSetupView(store: store)
        } else {
          GitHubUnavailableView(store: store)
        }
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            if let error = store.errorMessage { errorBanner(error) }
            ForEach(store.preferences.sections) { section in
              sectionView(section)
            }
          }
        }
        .background(OverlayScrollViewConfigurator())
      }
      Divider()
      footer
    }
    .frame(
      minWidth: 310, idealWidth: surface == .menuBar ? 390 : 410, minHeight: 320, idealHeight: 590
    )
    .background(.regularMaterial)
    .overlay(alignment: .bottomTrailing) {
      if case .panel = surface {
        ResizeGrip()
          .padding(5)
          .allowsHitTesting(false)
      }
    }
    .task { store.start() }
  }

  private var header: some View {
    HStack(spacing: 10) {
      OcticonImage(icon: .pullRequest, size: 17)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 0) {
        Text("Pull Requests").font(.headline)
        if let login = store.viewerLogin {
          Text("@\(login)").font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button {
        store.refresh()
      } label: {
        if store.isRefreshing {
          ProgressView()
            .controlSize(.small)
            .frame(width: 16, height: 16)
        } else {
          Image(systemName: "arrow.clockwise")
            .frame(width: 16, height: 16)
        }
      }
      .buttonStyle(.borderless)
      .disabled(store.isRefreshing)
      .help("Refresh now")
      if surface == .menuBar {
        Button {
          togglePanel?()
        } label: {
          Image(systemName: "macwindow.on.rectangle")
        }
        .buttonStyle(.borderless)
        .help("Show floating panel")
      }
      Button {
        openSettings?()
      } label: {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.borderless)
      .help("Settings")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
  }

  @ViewBuilder
  private func sectionView(_ section: PRSection) -> some View {
    let items = store.pullRequests(in: section)
    VStack(spacing: 0) {
      Button {
        store.toggleCollapse(section)
      } label: {
        HStack(spacing: 7) {
          Image(systemName: section.isCollapsed ? "chevron.right" : "chevron.down")
            .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
          Text(section.name).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
          Spacer()
          Text("\(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(section.isCollapsed ? "Show \(section.name)" : "Hide \(section.name)")
      if !section.isCollapsed {
        if items.isEmpty {
          Text(store.isRefreshing ? "Checking…" : "No pull requests")
            .font(.caption).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30).padding(.bottom, 9)
        } else {
          ForEach(items) { pullRequest in
            PullRequestRow(
              pullRequest: pullRequest,
              preferences: store.preferences,
              open: { store.open(pullRequest) },
              dismiss: { store.dismiss(pullRequest) }
            )
            if pullRequest.id != items.last?.id { Divider().padding(.leading, 30) }
          }
        }
      }
    }
  }

  private func errorBanner(_ message: String) -> some View {
    Label(
      store.connectionIssue == .authentication
        ? "GitHub sign-in needs attention. Showing saved results."
        : "Refresh unavailable. GitHub may be having issues; your saved results are still shown.",
      systemImage: "exclamationmark.triangle.fill"
    )
    .font(.caption).foregroundStyle(.orange)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10).background(.orange.opacity(0.08))
    .help(message)
  }

  private var footer: some View {
    HStack {
      if store.isRefreshing {
        ProgressView().controlSize(.small)
        Text("Refreshing…")
      } else if let date = store.lastUpdated {
        Text(date.updatedLabel)
      } else {
        Text("Not updated yet")
      }
      Spacer()
    }
    .font(.caption).foregroundStyle(.secondary)
    .padding(.horizontal, 13).padding(.vertical, 8)
  }
}

private struct OverlayScrollViewConfigurator: NSViewRepresentable {
  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.attach(to: view)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.attach(to: nsView)
  }

  final class Coordinator {
    private weak var scrollView: NSScrollView?
    private var resignObserver: NSObjectProtocol?

    deinit {
      if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func attach(to view: NSView) {
      DispatchQueue.main.async { [weak self, weak view] in
        guard let self, let scrollView = view?.enclosingScrollView else { return }
        self.scrollView = scrollView
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        if self.resignObserver == nil {
          self.resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
          ) { [weak self] _ in
            self?.scrollView?.verticalScroller?.animator().alphaValue = 0
          }
        }
      }
    }
  }
}

private struct PullRequestRow: View {
  let pullRequest: PullRequest
  let preferences: Preferences
  let open: () -> Void
  let dismiss: () -> Void
  @State private var hovering = false

  private var displayedDate: Date {
    if preferences.timeDisplayMode == .reviewRequested {
      return pullRequest.reviewRequestedAt ?? pullRequest.createdAt
    }
    return pullRequest.createdAt
  }

  var body: some View {
    Button(action: handleClick) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          Text(pullRequest.repository).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .lineLimit(1)
          Text(verbatim: "#\(pullRequest.number)").font(.caption.monospacedDigit()).foregroundStyle(
            .tertiary)
          if let position = pullRequest.stackPosition, let size = pullRequest.stackSize, size > 1 {
            StackBadge(position: position, size: size)
          }
          if pullRequest.isDraft { DraftBadge() }
        }
        Text(pullRequest.title).font(.callout).foregroundStyle(.primary).lineLimit(2)
          .multilineTextAlignment(.leading)
        HStack(spacing: 7) {
          if preferences.showAuthor {
            AvatarView(url: pullRequest.authorAvatarURL)
            Text(pullRequest.author).lineLimit(1)
          }
          if preferences.showAuthor && preferences.showUpdatedAt { Text("·") }
          if preferences.showUpdatedAt {
            Text(displayedDate.ageLabel)
              .help(preferences.timeDisplayMode == .created ? "PR created" : "Review requested")
          }
          if preferences.statusDisplayMode == .compactIcons {
            Spacer(minLength: 4)
            if preferences.showReviewStatus { reviewLabel(showText: false) }
            if preferences.showCheckStatus { checkLabel(showText: false) }
          }
        }
        .font(.caption).foregroundStyle(.secondary)
        if preferences.statusDisplayMode == .labeled
          && (preferences.showReviewStatus || preferences.showCheckStatus)
        {
          HStack(spacing: 10) {
            if preferences.showReviewStatus { reviewLabel(showText: true) }
            if preferences.showCheckStatus { checkLabel(showText: true) }
          }
          .padding(.top, 1)
        }
      }
      .padding(.horizontal, 13).padding(.vertical, 9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(hovering ? Color.primary.opacity(0.055) : .clear)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help(Text(verbatim: "Open #\(pullRequest.number) on GitHub"))
    .contextMenu {
      Button("Open on GitHub", action: open)
      Button("Copy URL") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pullRequest.url.absoluteString, forType: .string)
      }
      Button("Copy Branch") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pullRequest.branch, forType: .string)
      }
    }
  }

  private func handleClick() {
    if preferences.commandClickDismisses,
      NSApp.currentEvent?.modifierFlags.contains(.command) == true
    {
      dismiss()
    } else {
      open()
    }
  }

  @ViewBuilder private func checkLabel(showText: Bool) -> some View {
    switch pullRequest.checksState {
    case .success:
      StatusLabel(icon: .checksPassed, text: "Checks passed", color: .green, showText: showText)
    case .failure:
      StatusLabel(icon: .checksFailed, text: "Checks failed", color: .red, showText: showText)
    case .pending:
      StatusLabel(icon: .checksRunning, text: "Checks running", color: .orange, showText: showText)
    case .neutral:
      if showText {
        Label("No required checks", systemImage: "minus.circle")
          .font(.caption2).foregroundStyle(.secondary)
          .help("No required checks")
      } else {
        Image(systemName: "minus.circle")
          .help("No required checks").accessibilityLabel("No required checks")
      }
    case .unknown: EmptyView()
    }
  }

  @ViewBuilder private func reviewLabel(showText: Bool) -> some View {
    switch pullRequest.reviewDecision {
    case "APPROVED":
      StatusLabel(icon: .approved, text: "Approved", color: .green, showText: showText)
    case "CHANGES_REQUESTED":
      StatusLabel(
        icon: .changesRequested, text: "Changes requested", color: .red, showText: showText)
    case "REVIEW_REQUIRED":
      StatusLabel(
        icon: .reviewPending, text: "Review pending", color: .yellow, showText: showText,
        iconScale: 2)
    default:
      EmptyView()
    }
  }
}

private struct ResizeGrip: View {
  var body: some View {
    Canvas { context, size in
      for inset in stride(from: CGFloat(0), through: 8, by: 4) {
        var path = Path()
        path.move(to: CGPoint(x: size.width - inset, y: size.height))
        path.addLine(to: CGPoint(x: size.width, y: size.height - inset))
        context.stroke(path, with: .color(.secondary.opacity(0.42)), lineWidth: 1)
      }
    }
    .frame(width: 12, height: 12)
    .accessibilityHidden(true)
  }
}

private struct StatusLabel: View {
  let icon: Octicon
  let text: String
  let color: Color
  let showText: Bool
  var iconScale: CGFloat = 1

  var body: some View {
    HStack(spacing: 4) {
      OcticonImage(icon: icon, size: 11)
        .foregroundStyle(color)
        .scaleEffect(iconScale)
      if showText { Text(text).foregroundStyle(.secondary) }
    }
    .font(.caption2)
    .help(text)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
  }
}

private struct DraftBadge: View {
  var body: some View {
    HStack(spacing: 3) {
      OcticonImage(icon: .draft, size: 10)
      Text("Draft")
    }
    .font(.caption2.weight(.medium))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 5)
    .padding(.vertical, 2)
    .background(Color.primary.opacity(0.08), in: Capsule())
    .help("Draft pull request")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Draft")
  }
}

private struct StackBadge: View {
  let position: Int
  let size: Int

  var body: some View {
    HStack(spacing: 3) {
      OcticonImage(icon: .stack, size: 10)
      Text(verbatim: "\(position)/\(size)")
    }
    .font(.caption2.weight(.medium).monospacedDigit())
    .foregroundStyle(.secondary)
    .padding(.horizontal, 5)
    .padding(.vertical, 2)
    .background(Color.primary.opacity(0.06), in: Capsule())
    .help(Text(verbatim: "Stacked pull request \(position) of \(size)"))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: "Stacked pull request \(position) of \(size)"))
  }
}

private struct AvatarView: View {
  let url: URL?

  var body: some View {
    AsyncImage(url: url) { phase in
      if let image = phase.image {
        image.resizable().scaledToFill()
      } else {
        Image(systemName: "person.crop.circle.fill")
          .resizable().foregroundStyle(.tertiary)
      }
    }
    .frame(width: 14, height: 14)
    .clipShape(Circle())
  }
}

private struct GitHubSetupView: View {
  @ObservedObject var store: AppStore

  var body: some View {
    ContentUnavailableView {
      Label("Connect GitHub", systemImage: "person.crop.circle.badge.exclamationmark")
    } description: {
      Text(
        "Glance uses the account signed in through GitHub CLI. Install it, run “gh auth login,” then try again."
      )
    } actions: {
      HStack {
        Link("Get GitHub CLI", destination: URL(string: "https://cli.github.com/")!)
        Button("Try Again") { store.refresh() }
          .help("Check your GitHub connection")
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct GitHubUnavailableView: View {
  @ObservedObject var store: AppStore

  var body: some View {
    ContentUnavailableView {
      Label("GitHub is unavailable", systemImage: "icloud.slash")
    } description: {
      Text("Glance will retry automatically. No saved pull requests are available yet.")
    } actions: {
      Button("Try Again") { store.refresh() }
        .help("Retry GitHub now")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
