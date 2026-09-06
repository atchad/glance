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
  @State private var selectedPullRequestID: DashboardNavigation.RowID?
  @FocusState private var isSearchFocused: Bool
  @FocusState private var isDashboardFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      searchField
      Divider()
      if let message = store.storageErrorMessage { errorBanner(message) }
      if store.errorMessage != nil, store.snapshots.isEmpty {
        if store.connectionIssue == .authentication {
          GitHubSetupView(store: store)
        } else {
          GitHubUnavailableView(store: store)
        }
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
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
      if let dismissal = store.dismissalToUndo {
        DismissalUndoBanner(store: store, title: dismissal.title)
          .padding(.horizontal, 10).padding(.vertical, 6)
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
    .onChange(of: navigation.rows.map(\.id)) { _, _ in
      selectedPullRequestID = navigation.reconciled(selectedPullRequestID)
    }
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
        .help("Search pull requests (/)")
      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear search")
        .accessibilityLabel("Clear search")
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
      .help("Refresh now (R)")
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
      .accessibilityLabel("Settings")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
  }

  @ViewBuilder
  private func sectionView(_ section: PRSection) -> some View {
    let items = navigation.items(in: section.id)
    Section {
      if !section.isCollapsed {
        if let error = store.sectionErrors[section.id] {
          Label(error, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange)
            .textSelection(.enabled)
            .padding(.horizontal, 13).padding(.vertical, 6)
        }
        if items.isEmpty {
          Text(
            store.isRefreshing ? "Checking…"
              : store.sectionErrors[section.id] != nil ? "No saved pull requests"
              : store.snapshots[section.id] == nil ? "Not loaded yet"
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
              isSelected: selectedPullRequestID == rowID(section, pullRequest),
              select: { selectedPullRequestID = rowID(section, pullRequest) }
            )
            .id(rowID(section, pullRequest))
            if pullRequest.id != items.last?.id {
              Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .padding(.horizontal, 13)
                .accessibilityHidden(true)
            }
          }
        }
      }
    } header: {
      Button {
        store.toggleCollapse(section)
      } label: {
        HStack(spacing: 7) {
          Image(systemName: section.isCollapsed ? "chevron.right" : "chevron.down")
            .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
          Text(section.name).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
          Spacer()
          Text(store.snapshots[section.id] == nil || store.sectionErrors[section.id] != nil
            ? "—" : "\(items.count)")
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 13).padding(.vertical, 5)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(section.isCollapsed ? "Collapsed" : "Expanded")
      .help(section.isCollapsed ? "Show \(section.name)" : "Hide \(section.name)")
      .background(.regularMaterial)
    }
  }

  private var navigation: DashboardNavigation {
    DashboardNavigation(
      sections: store.preferences.sections.map { ($0, store.pullRequests(in: $0)) },
      query: searchText)
  }

  private func rowID(_ section: PRSection, _ pullRequest: PullRequest) -> DashboardNavigation.RowID {
    .init(sectionID: section.id, pullRequestID: pullRequest.id)
  }

  private var snoozedSection: some View {
    Section {
      ForEach(filtered(store.snoozedPullRequests)) { pullRequest in
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 2) {
            Text("\(pullRequest.repository) #\(String(pullRequest.number))")
              .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(pullRequest.title).font(.callout).lineLimit(1)
          }
          Spacer()
          Button("Wake") { store.unsnooze(pullRequest) }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
      }
    } header: {
      HStack {
        Image(systemName: "clock")
        Text("Snoozed").font(.subheadline.weight(.medium))
        Spacer()
        Text("\(store.snoozedPullRequests.count)").font(.caption.monospacedDigit())
      }
      .foregroundStyle(.secondary).padding(.horizontal, 13).padding(.vertical, 5)
      .background(.regularMaterial)
    }
  }

  private func filtered(_ pullRequests: [PullRequest]) -> [PullRequest] {
    DashboardNavigation.filtered(pullRequests, query: searchText)
  }

  private func moveSelection(by offset: Int) {
    selectedPullRequestID = navigation.moved(from: selectedPullRequestID, by: offset)
  }

  private func performSelected(_ action: (PullRequest) -> Void) -> KeyPress.Result {
    guard let pullRequest = navigation.pullRequest(for: selectedPullRequestID)
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
      message,
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

private struct DismissalUndoBanner: View {
  @ObservedObject var store: AppStore
  let title: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovered = false
  @State private var pauseID = UUID()
  @FocusState private var isFocused: Bool
  @AccessibilityFocusState private var isAccessibilityFocused: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "arrow.uturn.backward.circle.fill")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text("Dismissed “\(title)”")
        .font(.callout)
        .lineLimit(1)
        .help(title)
      Spacer(minLength: 0)
      Button("Undo", action: store.undoDismissal)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .focused($isFocused)
        .accessibilityFocused($isAccessibilityFocused)
        .help("Restore the last dismissed pull request")
    }
    .padding(10)
    .background(alignment: .leading) {
      GeometryReader { geometry in
        Color.accentColor.opacity(0.10)
          .frame(width: geometry.size.width * (reduceMotion ? 1 : store.dismissalUndoProgress))
          .animation(reduceMotion ? nil : .linear(duration: 0.05), value: store.dismissalUndoProgress)
      }
      .accessibilityHidden(true)
    }
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator.opacity(0.5)))
    .onHover { hovered in
      isHovered = hovered
      store.pauseDismissalUndo(hovered || isFocused || isAccessibilityFocused, source: pauseID)
    }
    .onChange(of: isFocused) { _, _ in updatePause() }
    .onChange(of: isAccessibilityFocused) { _, _ in updatePause() }
    .onDisappear { store.pauseDismissalUndo(false, source: pauseID) }
  }

  private func updatePause() {
    store.pauseDismissalUndo(isHovered || isFocused || isAccessibilityFocused, source: pauseID)
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
      return pullRequest.personalReviewRequestedAt ?? pullRequest.createdAt
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
            .primary)
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
    .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        .help("Pin or unpin the selected pull request (P)")
      Menu("Snooze") {
        Button("For one hour") { snooze(.until(Date().addingTimeInterval(3_600))) }
        Button("Until this time tomorrow") {
          snooze(.until(Calendar.current.date(byAdding: .day, value: 1, to: Date())!))
        }
        Button("For one week") {
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
      StatusLabel(icon: .checksPassed, text: "Checks passed", color: .statusGreen, showText: showText)
    case .failure:
      StatusLabel(icon: .checksFailed, text: "Checks failed", color: .red, showText: showText)
    case .pending:
      StatusLabel(icon: .checksRunning, text: "Checks running", color: .orange, showText: showText)
    case .neutral:
      if showText {
        Label("Checks neutral", systemImage: "minus.circle")
          .font(.caption2).foregroundStyle(.secondary)
          .help("Checks neutral")
      } else {
        Image(systemName: "minus.circle")
          .help("Checks neutral").accessibilityLabel("Checks neutral")
      }
    case .unknown: EmptyView()
    }
  }

  @ViewBuilder private func reviewLabel(showText: Bool) -> some View {
    switch pullRequest.reviewDecision {
    case "APPROVED":
      StatusLabel(icon: .approved, text: "Approved", color: .statusGreen, showText: showText)
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
    case .reviewRequestUnknown: "questionmark.circle"
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
    Label {
      Text(summary.message).foregroundStyle(.primary)
    } icon: {
      Image(systemName: symbol).foregroundStyle(color)
    }
      .font(.caption2.weight(.medium))
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
      Label(store.refreshBlockedUntil == nil ? "Couldn’t refresh pull requests" : "Refresh paused",
        systemImage: "icloud.slash")
    } description: {
      Text(store.errorMessage ?? "Try refreshing again.")
        .textSelection(.enabled)
    } actions: {
      Button("Try Again") { store.refresh() }
        .help("Retry GitHub now")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
