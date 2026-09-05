import AppKit
import SwiftUI

enum DashboardSurface { case menuBar, panel }

struct DashboardView: View {
  @ObservedObject var store: AppStore
  var surface: DashboardSurface
  var togglePanel: (() -> Void)?
  var openSettings: (() -> Void)?
  var didOpenPullRequest: (() -> Void)?
  @State private var searchText = ""
  @State private var selectedPullRequestID: String?
  @FocusState private var isSearchFocused: Bool
  @FocusState private var isDashboardFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      searchField
      Divider()
      if store.errorMessage != nil, store.snapshots.isEmpty {
        if store.connectionIssue == .authentication {
          GitHubSetupView(store: store)
        } else {
          GitHubUnavailableView(store: store)
        }
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 0) {
              Color.clear.frame(height: 0).id("dashboard-top")
              if let error = store.errorMessage { errorBanner(error) }
              ForEach(store.preferences.sections) { section in
                sectionView(section)
              }
              if !store.snoozedPullRequests.isEmpty { snoozedSection }
            }
            .background(OverlayScrollViewConfigurator())
          }
          .onChange(of: searchText) { _, _ in
            proxy.scrollTo("dashboard-top", anchor: .top)
          }
          .onChange(of: selectedPullRequestID) { _, id in
            if let id { proxy.scrollTo(id, anchor: .center) }
          }
        }
      }
      Divider()
      footer
    }
    .frame(
      minWidth: 310, idealWidth: surface == .menuBar ? 390 : 410, minHeight: 320, idealHeight: 590
    )
    .background(.regularMaterial)
    .focusable()
    .focused($isDashboardFocused)
    .onAppear { isDashboardFocused = true }
    .onKeyPress(.downArrow) {
      guard !isSearchFocused else { return .ignored }
      moveSelection(by: 1)
      return .handled
    }
    .onKeyPress(.upArrow) {
      guard !isSearchFocused else { return .ignored }
      moveSelection(by: -1)
      return .handled
    }
    .onKeyPress("j") {
      guard !isSearchFocused else { return .ignored }
      moveSelection(by: 1)
      return .handled
    }
    .onKeyPress("k") {
      guard !isSearchFocused else { return .ignored }
      moveSelection(by: -1)
      return .handled
    }
    .onKeyPress("/") {
      guard !isSearchFocused else { return .ignored }
      isSearchFocused = true
      return .handled
    }
    .onKeyPress(.return) {
      guard !isSearchFocused else { return .ignored }
      return performSelected { openPullRequest($0) }
    }
    .onKeyPress("d") {
      guard !isSearchFocused else { return .ignored }
      return performSelected { store.dismiss($0) }
    }
    .onKeyPress("p") {
      guard !isSearchFocused else { return .ignored }
      return performSelected { store.togglePin($0) }
    }
    .onKeyPress("r") {
      guard !isSearchFocused else { return .ignored }
      store.refresh()
      return .handled
    }
    .overlay(alignment: .bottomTrailing) {
      if case .panel = surface {
        ResizeGrip()
          .padding(5)
          .allowsHitTesting(false)
      }
    }
    .task { store.start() }
  }

  private var searchField: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("Search pull requests", text: $searchText)
        .textFieldStyle(.plain)
        .focused($isSearchFocused)
      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear search")
      }
    }
    .padding(.horizontal, 9)
    .frame(height: 28)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    .padding(.horizontal, 10)
    .padding(.bottom, 9)
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
    let items = filtered(store.pullRequests(in: section))
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
          Text(
            store.isRefreshing ? "Checking…"
              : searchText.isEmpty ? "No pull requests" : "No matches")
            .font(.caption).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30).padding(.bottom, 9)
        } else {
          ForEach(items) { pullRequest in
            PullRequestRow(
              pullRequest: pullRequest,
              preferences: store.preferences,
              open: {
                store.open(pullRequest)
                didOpenPullRequest?()
              },
              dismiss: { store.dismiss(pullRequest) },
              togglePin: { store.togglePin(pullRequest) },
              snooze: { store.snooze(pullRequest, condition: $0) },
              isPinned: store.preferences.pinnedPullRequests.contains(pullRequest.id),
              isSelected: selectedPullRequestID == pullRequest.id,
              select: { selectedPullRequestID = pullRequest.id }
            )
            .id(pullRequest.id)
            if pullRequest.id != items.last?.id { Divider().padding(.leading, 30) }
          }
        }
      }
    }
  }

  private var visiblePullRequests: [PullRequest] {
    var seen: Set<String> = []
    return store.preferences.sections.flatMap { filtered(store.pullRequests(in: $0)) }
      .filter { seen.insert($0.id).inserted }
  }

  private var snoozedSection: some View {
    VStack(spacing: 0) {
      HStack {
        Image(systemName: "clock")
        Text("Snoozed").font(.subheadline.weight(.medium))
        Spacer()
        Text("\(store.snoozedPullRequests.count)").font(.caption.monospacedDigit())
      }
      .foregroundStyle(.secondary).padding(.horizontal, 13).padding(.vertical, 8)
      ForEach(filtered(store.snoozedPullRequests)) { pullRequest in
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(pullRequest.repository) #\(pullRequest.number)")
              .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(pullRequest.title).font(.callout).lineLimit(1)
          }
          Spacer()
          Button("Wake") { store.unsnooze(pullRequest) }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
      }
    }
  }

  private func filtered(_ pullRequests: [PullRequest]) -> [PullRequest] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return pullRequests }
    return pullRequests.filter {
      [$0.title, $0.repository, $0.author, $0.branch, "#\($0.number)", $0.attention.message]
        .joined(separator: " ").localizedCaseInsensitiveContains(query)
        || $0.labels.contains { $0.localizedCaseInsensitiveContains(query) }
    }
  }

  private func moveSelection(by offset: Int) {
    let items = visiblePullRequests
    guard !items.isEmpty else { selectedPullRequestID = nil; return }
    let current = selectedPullRequestID.flatMap { id in items.firstIndex { $0.id == id } }
      ?? (offset > 0 ? -1 : 0)
    selectedPullRequestID = items[(current + offset + items.count) % items.count].id
  }

  private func performSelected(_ action: (PullRequest) -> Void) -> KeyPress.Result {
    guard let id = selectedPullRequestID,
      let pullRequest = visiblePullRequests.first(where: { $0.id == id })
    else { return .ignored }
    action(pullRequest)
    return .handled
  }

  private func openPullRequest(_ pullRequest: PullRequest) {
    store.open(pullRequest)
    didOpenPullRequest?()
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
    let view = ScrollViewProbe()
    view.didAttach = { [weak coordinator = context.coordinator, weak view] in
      guard let view else { return }
      coordinator?.attach(to: view)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.attach(to: nsView)
  }

  private final class ScrollViewProbe: NSView {
    var didAttach: (() -> Void)?

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      DispatchQueue.main.async { [weak self] in self?.didAttach?() }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      DispatchQueue.main.async { [weak self] in self?.didAttach?() }
    }
  }

  final class Coordinator {
    private weak var scrollView: NSScrollView?
    private var observers: [NSObjectProtocol] = []
    private var fallbackHide: DispatchWorkItem?
    private var isScrolling = false

    deinit { removeObservers() }

    func attach(to view: NSView) {
      DispatchQueue.main.async { [weak self, weak view] in
        guard let self, let scrollView = view?.enclosingScrollView else { return }
        guard self.scrollView !== scrollView else {
          scrollView.scrollerStyle = .overlay
          scrollView.autohidesScrollers = true
          if !self.isScrolling { self.hideScroller() }
          return
        }

        self.removeObservers()
        self.scrollView = scrollView
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        self.hideScroller()
        self.observeScrollActivity(on: scrollView)
      }
    }

    private func observeScrollActivity(on scrollView: NSScrollView) {
      let center = NotificationCenter.default
      observers = [
        center.addObserver(
          forName: NSScrollView.willStartLiveScrollNotification,
          object: scrollView,
          queue: .main
        ) { [weak self] _ in self?.showScroller() },
        center.addObserver(
          forName: NSScrollView.didLiveScrollNotification,
          object: scrollView,
          queue: .main
        ) { [weak self] _ in self?.showScrollerWithFallbackHide() },
        center.addObserver(
          forName: NSScrollView.didEndLiveScrollNotification,
          object: scrollView,
          queue: .main
        ) { [weak self] _ in self?.hideScroller() },
        center.addObserver(
          forName: NSApplication.didResignActiveNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in self?.hideScroller() },
      ]
    }

    private func showScroller() {
      fallbackHide?.cancel()
      isScrolling = true
      guard let scroller = scrollView?.verticalScroller else { return }
      scroller.isHidden = false
      scroller.alphaValue = 1
    }

    private func showScrollerWithFallbackHide() {
      showScroller()
      let work = DispatchWorkItem { [weak self] in self?.hideScroller() }
      fallbackHide = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func hideScroller() {
      fallbackHide?.cancel()
      fallbackHide = nil
      isScrolling = false
      guard let scroller = scrollView?.verticalScroller else { return }
      scroller.alphaValue = 0
      scroller.isHidden = true
    }

    private func removeObservers() {
      fallbackHide?.cancel()
      fallbackHide = nil
      observers.forEach(NotificationCenter.default.removeObserver)
      observers.removeAll()
    }
  }
}

private struct PullRequestRow: View {
  let pullRequest: PullRequest
  let preferences: Preferences
  let open: () -> Void
  let dismiss: () -> Void
  let togglePin: () -> Void
  let snooze: (SnoozeCondition) -> Void
  let isPinned: Bool
  let isSelected: Bool
  let select: () -> Void
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
          if isPinned {
            Image(systemName: "pin.fill")
              .font(.caption2).foregroundStyle(.secondary)
              .help("Pinned")
              .accessibilityLabel("Pinned pull request")
          }
        }
        Text(pullRequest.title).font(.callout).foregroundStyle(.primary).lineLimit(2)
          .multilineTextAlignment(.leading)
        if preferences.showAttentionReason, pullRequest.attention.reason != .draft {
          AttentionReasonLabel(summary: pullRequest.attention)
        }
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
          if preferences.showLineChanges {
            if preferences.showAuthor || preferences.showUpdatedAt { Text("·") }
            HStack(spacing: 4) {
              Text(verbatim: "+\(pullRequest.additions)").foregroundStyle(.green)
              Text(verbatim: "−\(pullRequest.deletions)").foregroundStyle(.red)
            }
            .fontDesign(.monospaced)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
              "\(pullRequest.additions) additions, \(pullRequest.deletions) deletions")
            .help("Lines changed")
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
      .background(
        isSelected ? Color.accentColor.opacity(0.16)
          : hovering ? Color.primary.opacity(0.055) : .clear)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .simultaneousGesture(TapGesture().onEnded(select))
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
      Divider()
      Button(isPinned ? "Unpin" : "Pin", action: togglePin)
      Menu("Snooze") {
        Button("For 1 Hour") { snooze(.until(Date().addingTimeInterval(3_600))) }
        Button("Until Tomorrow") {
          snooze(.until(Calendar.current.date(byAdding: .day, value: 1, to: Date())!))
        }
        Button("Until Next Week") {
          snooze(.until(Calendar.current.date(byAdding: .day, value: 7, to: Date())!))
        }
        Button("Until This Pull Request Changes") {
          snooze(.revisionChanges(pullRequest.revisionKey))
        }
        if pullRequest.checksState == .pending {
          Button("Until Checks Finish") {
            snooze(.checksComplete(pullRequest.revisionKey))
          }
        }
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
      PendingReviewLabel(showText: showText)
    default:
      EmptyView()
    }
  }
}

private struct AttentionReasonLabel: View {
  let summary: PRAttentionSummary

  private var symbol: String {
    switch summary.reason {
    case .reviewRequested, .reviewRerequested, .commitsSinceReview: "person.crop.circle.badge.clock"
    case .changesRequested, .checksFailing, .mergeConflict: "exclamationmark.circle.fill"
    case .unresolvedConversations: "bubble.left.and.exclamationmark.bubble.right"
    case .checksPending: "clock"
    case .branchBehind: "arrow.triangle.branch"
    case .waitingForReviews: "person.2"
    case .readyToMerge: "checkmark.circle.fill"
    case .autoMerge: "arrow.triangle.merge"
    case .mergeQueue: "text.line.first.and.arrowtriangle.forward"
    case .draft: "pencil.circle"
    case .merged: "arrow.triangle.merge"
    case .closed: "xmark.circle"
    case .active: "circle.fill"
    }
  }

  private var color: Color {
    switch summary.reason {
    case .changesRequested, .checksFailing, .mergeConflict: .red
    default: summary.level.color
    }
  }

  var body: some View {
    Label(summary.message, systemImage: symbol)
      .font(.caption2.weight(.medium))
      .foregroundStyle(color)
      .lineLimit(1)
      .help(summary.message)
      .accessibilityLabel("Attention status: \(summary.message)")
  }
}

private struct PendingReviewLabel: View {
  let showText: Bool

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(.yellow)
        .frame(width: 11, height: 11)
      if showText { Text("Review pending").foregroundStyle(.secondary) }
    }
    .font(.caption2)
    .help("Review pending")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Review pending")
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

  var body: some View {
    HStack(spacing: 4) {
      OcticonImage(icon: icon, size: 11)
        .foregroundStyle(color)
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
