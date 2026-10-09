import AppKit
import SwiftUI

struct DashboardView: View {
  @ObservedObject var store: AppStore
  @ObservedObject var keys: KeybindingStore
  let commands: ApplicationCommands
  var isMenuBar = false
  var close: (() -> Void)?
  @State private var searchText = ""
  @State private var snoozedIsCollapsed = true
  @State private var detailRowID: DashboardNavigation.RowID?
  @State private var selectedPullRequestID: DashboardNavigation.RowID?
  @State private var matcher = KeybindingMatcher()
  @State private var sequenceExpiry: Task<Void, Never>?
  @FocusState private var isSearchFocused: Bool
  @FocusState private var isDashboardFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      searchField
      Divider()
      if let message = store.storageErrorMessage { errorBanner(message) }
      if let message = store.linkOpeningErrorMessage { errorBanner(message) }
      ForEach(store.mergeActionErrors.keys.sorted(), id: \.self) { id in
        if let message = store.mergeActionErrors[id] { errorBanner(message) }
      }
      if let message = keys.errorMessage ?? keys.registrationError { errorBanner(message) }
      if store.errorMessage != nil, store.snapshots.isEmpty {
        if store.connectionIssue == .authentication {
          GitHubSetupView(store: store, refresh: { perform(.refresh) })
        } else {
          GitHubUnavailableView(store: store, refresh: { perform(.refresh) })
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
          DismissalUndoBanner(store: store, title: dismissal.title, undo: { perform(.undoDismissal) })
          .padding(.horizontal, 10).padding(.vertical, 6)
      }
      Divider()
      if !matcher.prefix.isEmpty { sequenceHints }
      footer
    }
    .frame(
      minWidth: 310, idealWidth: isMenuBar ? 390 : 410, minHeight: 320, idealHeight: 590
    )
    .background(.regularMaterial)
    .background {
      Color.clear
        .focusable()
        .focusEffectDisabled()
        .focused($isDashboardFocused)
        .accessibilityHidden(true)
    }
    .onAppear { isDashboardFocused = true }
    .background(DashboardKeyboardInput(handle: handleKey, cancel: cancelSequence))
    .onDisappear { cancelSequence() }
    .onChange(of: keys.resolved.configuration) { _, _ in cancelSequence() }
    .onChange(of: isSearchFocused) { _, _ in cancelSequence() }
    .onChange(of: detailRowID) { _, _ in cancelSequence() }
    .onChange(of: navigation.rows.map(\.id)) { _, _ in
      cancelSequence()
      let reconciledSelection = navigation.reconciled(selectedPullRequestID)
      let lostFocusedRow = reconciledSelection != selectedPullRequestID
        || navigation.reconciled(detailRowID) != detailRowID
      selectedPullRequestID = reconciledSelection
      detailRowID = navigation.reconciled(detailRowID)
      if lostFocusedRow, !isSearchFocused {
        // A removed AppKit trigger can leave the panel itself as first responder.
        // Restore focus after SwiftUI has removed the row and dismissed its popover.
        isDashboardFocused = false
        DispatchQueue.main.async {
          if !isSearchFocused, detailRowID == nil { isDashboardFocused = true }
        }
      }
    }
    .overlay(alignment: .bottomTrailing) {
      if !isMenuBar {
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
        .help(keys.help(for: .search))
      if !searchText.isEmpty {
        Button {
          perform(.clearSearch)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(keys.help(for: .clearSearch))
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
      if isMenuBar {
        Button { perform(.showPanel) } label: {
          Image(systemName: "rectangle.arrowtriangle.2.outward")
        }
        .buttonStyle(.borderless)
        .nativeHelp(keys.help(for: .showPanel))
        .accessibilityLabel("Show floating panel")
      }
      Button {
        perform(.refresh)
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
      .nativeHelp(keys.help(for: .refresh))
      Button {
        perform(.settings)
      } label: {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.borderless)
      .nativeHelp(keys.help(for: .settings))
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
              keys: keys,
              perform: { perform($0, target: target(for: pullRequest, section: section)) },
              editRepositoryColor: {
                detailRowID = nil
                close?()
                commands.showRepositoryColors(for: pullRequest.repository)
              },
              isPinned: store.preferences.pinnedPullRequests.contains(pullRequest.id),
              isSelected: selectedPullRequestID == rowID(section, pullRequest),
              select: { selectedPullRequestID = rowID(section, pullRequest) },
              isShowingDetails: Binding(
                get: { detailRowID == rowID(section, pullRequest) },
                set: { detailRowID = $0 ? rowID(section, pullRequest) : nil }),
              checksAreCached: store.isShowingCachedData || store.errorMessage != nil
                || store.sectionErrors[section.id] != nil
                || store.lastUpdated.map { Date().timeIntervalSince($0) > store.preferences.refreshInterval } != false,
              openLink: { store.openLink($0) },
              isMerging: store.mergingPullRequestIDs.contains(pullRequest.id),
              mergeError: store.mergeActionErrors[pullRequest.id],
              merge: { Task { await store.performMergeAction(for: pullRequest) } }
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
        perform(.toggleSection, target: CommandTarget(section: section))
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
      query: searchText, snoozed: store.snoozedPullRequests,
      snoozedIsCollapsed: snoozedIsCollapsed)
  }

  private func rowID(_ section: PRSection, _ pullRequest: PullRequest) -> DashboardNavigation.RowID {
    .init(sectionID: section.id, pullRequestID: pullRequest.id)
  }

  private var snoozedSection: some View {
    Section {
      if !snoozedIsCollapsed {
        ForEach(navigation.items(in: DashboardNavigation.snoozedSectionID)) { pullRequest in
          HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 4) {
                RepositoryNameLabel(repository: pullRequest.repository,
                  color: store.preferences.repositoryColor(for: pullRequest.repository),
                  editColor: { commands.showRepositoryColors(for: pullRequest.repository) })
                  .lineLimit(1)
                Text(verbatim: "#\(pullRequest.number)").foregroundStyle(.secondary).fixedSize()
              }
              .font(.caption)
              Text(pullRequest.title).font(.callout).lineLimit(1)
            }
            Spacer()
            Button("Wake") { perform(.wake, target: CommandTarget(pullRequest: pullRequest)) }
              .buttonStyle(.borderless).help(keys.help(for: .wake))
          }
          .contentShape(Rectangle())
          .onTapGesture {
            selectedPullRequestID = .init(sectionID: DashboardNavigation.snoozedSectionID, pullRequestID: pullRequest.id)
            isDashboardFocused = true
          }
          .background(selectedPullRequestID?.sectionID == DashboardNavigation.snoozedSectionID
            && selectedPullRequestID?.pullRequestID == pullRequest.id ? Color.accentColor.opacity(0.16) : .clear)
          .id(DashboardNavigation.RowID(sectionID: DashboardNavigation.snoozedSectionID, pullRequestID: pullRequest.id))
          .accessibilityAddTraits(selectedPullRequestID?.pullRequestID == pullRequest.id ? .isSelected : [])
          .padding(.horizontal, 13).padding(.vertical, 8)
        }
      }
    } header: {
      Button {
        snoozedIsCollapsed.toggle()
      } label: {
        HStack(spacing: 7) {
          Image(systemName: snoozedIsCollapsed ? "chevron.right" : "chevron.down")
            .font(.caption2.weight(.bold))
          Image(systemName: "clock")
          Text("Snoozed").font(.subheadline.weight(.medium))
          Spacer()
          Text("\(store.snoozedPullRequests.count)").font(.caption.monospacedDigit())
        }
        .foregroundStyle(.secondary).padding(.horizontal, 13).padding(.vertical, 5)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(snoozedIsCollapsed ? "Collapsed" : "Expanded")
      .help(snoozedIsCollapsed ? "Show Snoozed" : "Hide Snoozed")
      .background(.regularMaterial)
    }
  }

  private func navigate(_ action: GlanceAction) {
    // AppKit details buttons can own first responder while SwiftUI still reports dashboard focus.
    // Force a focus transition so Return acts on the newly selected row, not the old trigger.
    isDashboardFocused = false
    DispatchQueue.main.async { isDashboardFocused = true }
    switch action {
    case .firstPR: selectedPullRequestID = navigation.rows.first?.id
    case .lastPR: selectedPullRequestID = navigation.rows.last?.id
    default: selectedPullRequestID = navigation.moved(from: selectedPullRequestID, by: action == .nextPR ? 1 : -1)
    }
  }

  private var selectedTarget: CommandTarget {
    let pr = navigation.pullRequest(for: selectedPullRequestID)
    let section = store.preferences.sections.first { $0.id == selectedPullRequestID?.sectionID }
    return target(for: pr, section: section)
  }

  private func target(for pr: PullRequest?, section: PRSection?) -> CommandTarget {
    CommandTarget(
      pullRequest: pr, section: section,
      navigate: navigation.rows.isEmpty ? nil : navigate,
      focusSearch: { isSearchFocused = true },
      clearSearch: searchText.isEmpty ? nil : { searchText = "" },
      showDetails: pr == nil || section == nil ? nil : {
        if let pr, let section { detailRowID = rowID(section, pr) }
      },
      close: close, didOpen: isMenuBar ? close : nil)
  }

  private func perform(_ action: GlanceAction, target: CommandTarget? = nil) {
    _ = commands.perform(action, target: target ?? selectedTarget)
  }

  private func handleKey(_ chord: KeyChord, textEditing: Bool, nativeControl: Bool, isRepeat: Bool) -> Bool {
    if detailRowID != nil || (nativeControl && chord.modifiers.isEmpty
      && ["return", "space", "up", "down", "left", "right"].contains(chord.key)) {
      cancelSequence()
      return false
    }
    let target = selectedTarget
    let result = matcher.handle(chord, at: ProcessInfo.processInfo.systemUptime,
      bindings: keys.resolved, textEditing: textEditing || isSearchFocused, isRepeat: isRepeat,
      enabled: { commands.canPerform($0, target: target) })
    sequenceExpiry?.cancel()
    if let deadline = matcher.deadline {
      sequenceExpiry = Task { @MainActor in
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled else { return }
        cancelSequence()
      }
    }
    switch result {
    case .ignored: return false
    case .consumed: return true
    case .action(let action): return commands.perform(action, target: target)
    }
  }

  private func cancelSequence() {
    sequenceExpiry?.cancel()
    sequenceExpiry = nil
    matcher.reset()
  }

  private var sequenceHints: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(matcher.prefix.map(\.display).joined(separator: " → ") + " — Esc to cancel")
        .font(.caption.weight(.semibold))
      ForEach(matcher.continuations(in: keys.resolved, enabled: { commands.canPerform($0, target: selectedTarget) }), id: \.0.text) { sequence, action in
        HStack {
          Text(sequence.chords.dropFirst(matcher.prefix.count).map(\.display).joined(separator: " → "))
            .font(.caption.monospaced())
          Text(action.title).font(.caption)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10).background(.bar)
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
  let undo: () -> Void
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
      Button("Undo", action: undo)
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

struct PullRequestRow: View {
  private static let verticalInset: CGFloat = 11
  private static let summaryLineHeight: CGFloat = 17
  private static let detailButtonHeight: CGFloat = 22

  let pullRequest: PullRequest
  let preferences: Preferences
  @ObservedObject var keys: KeybindingStore
  let perform: (GlanceAction) -> Void
  let editRepositoryColor: () -> Void
  let isPinned: Bool
  let isSelected: Bool
  let select: () -> Void
  @Binding var isShowingDetails: Bool
  let checksAreCached: Bool
  var openLink: ((URL) -> Void)? = nil
  var isMerging = false
  var mergeError: String? = nil
  var merge: () -> Void = {}
  @State private var detailFocusRequest = 0
  @State private var hovering = false

  var body: some View {
    ZStack(alignment: .topTrailing) {
      rowButton
      DetailActionButton(
        label: "Details for \(pullRequest.repository) #\(pullRequest.number)",
        focusRequest: detailFocusRequest,
        help: keys.help(for: .details)
      ) {
        select()
        perform(.details)
      }
      .frame(width: 28, height: Self.detailButtonHeight)
      // Centered on the summary line.
      .padding(.top, Self.verticalInset + (Self.summaryLineHeight - Self.detailButtonHeight) / 2)
      .padding(.trailing, 5)
      .popover(isPresented: $isShowingDetails, arrowEdge: .trailing) {
        PullRequestDetailsView(pullRequest: pullRequest, checksAreCached: checksAreCached,
          copy: { perform(.copyTitle) },
          repositoryColor: preferences.repositoryColor(for: pullRequest.repository),
          openLink: openLink,
          editRepositoryColor: editRepositoryColor) {
          isShowingDetails = false
        }
      }
      .onChange(of: isShowingDetails) { _, showing in
        if !showing { detailFocusRequest += 1 }
      }
    }
    .overlayPreferenceValue(MergeControlBoundsKey.self) { anchor in
      GeometryReader { geometry in
        if let anchor {
          let bounds = geometry[anchor]
          PullRequestMergeButton(pullRequest: pullRequest, isBusy: isMerging, error: mergeError) {
            select()
            merge()
          }
          .frame(width: bounds.width, height: bounds.height)
          .position(x: bounds.midX, y: bounds.midY)
        }
      }
    }
  }

  private var rowButton: some View {
    Button(action: handleClick) {
      VStack(alignment: .leading, spacing: 4) {
        summaryLine
          .padding(.trailing, 20)
        Text(pullRequest.title).font(.callout).foregroundStyle(.primary).lineLimit(1)
          .multilineTextAlignment(.leading)
      }
      .padding(.horizontal, 13).padding(.vertical, Self.verticalInset)
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
    .accessibilityHint(Text(verbatim: "Open #\(pullRequest.number) on GitHub"))
    // A row-wide .help overrides every nested icon's caption in SwiftUI.
    .contextMenu {
      Button("Open on GitHub") { perform(.openPR) }.help(keys.help(for: .openPR))
      Button("Copy Title") { perform(.copyTitle) }.help(keys.help(for: .copyTitle))
      Button("Copy URL") { perform(.copyURL) }.help(keys.help(for: .copyURL))
      Button("Copy Branch") { perform(.copyBranch) }.help(keys.help(for: .copyBranch))
      Button("Change Repo Color…", action: editRepositoryColor)
      Divider()
      Button(isPinned ? "Unpin" : "Pin") { perform(.pin) }
        .help(keys.help(for: .pin))
      Menu("Snooze") {
        Button("For one hour") { perform(.snoozeHour) }.help(keys.help(for: .snoozeHour))
        Button("Until this time tomorrow") { perform(.snoozeTomorrow) }.help(keys.help(for: .snoozeTomorrow))
        Button("For one week") { perform(.snoozeWeek) }.help(keys.help(for: .snoozeWeek))
        Button("Until This Pull Request Changes") { perform(.snoozeChanges) }.help(keys.help(for: .snoozeChanges))
        if pullRequest.checksState == .pending {
          Button("Until Checks Finish") {
            perform(.snoozeChecks)
          }
        }
      }
    }
  }

  private func handleClick() {
    if preferences.commandClickDismisses,
      NSApp.currentEvent?.modifierFlags.contains(.command) == true
    {
      perform(.dismiss)
    } else {
      perform(.openPR)
    }
  }

  private var summaryLine: some View {
    HStack(spacing: 7) {
      HStack(spacing: 7) {
        if preferences.showReviewStatus || preferences.showCheckStatus { statusSlots }
        if preferences.showAttentionReason, let attention = pullRequest.rowAttention {
          AttentionReasonIcon(summary: attention).fixedSize()
        }
        identity.layoutPriority(1)
        if preferences.showAuthor { author }
        if preferences.showLineChanges { lineChanges }
      }
      // Not a Spacer, which would compete with the author for width.
      .frame(maxWidth: .infinity, alignment: .leading)
      if preferences.showUpdatedAt {
        let time = pullRequest.displayedTime(for: preferences.timeDisplayMode)
        ElapsedTimeLabel(date: time.date, event: time.mode.title)
      }
    }
    // Muted below standard secondary so the title stands apart from its metadata.
    .font(.caption).foregroundStyle(.secondary.opacity(0.8))
    .frame(minHeight: Self.summaryLineHeight)
  }

  // Fixed slots keep the status group aligned when a status is absent.
  private var statusSlots: some View {
    HStack(spacing: 4) {
      if preferences.showReviewStatus { reviewIcon.frame(width: 11, height: 11) }
      if preferences.showCheckStatus { checkIcon.frame(width: 11, height: 11) }
    }
  }

  private var identity: some View {
    HStack(spacing: 4) {
      RepositoryNameLabel(repository: pullRequest.repository,
        color: preferences.repositoryColor(for: pullRequest.repository), editColor: editRepositoryColor)
        .font(.caption.weight(.medium)).lineLimit(1)
      // Reserve the identity slot, but keep the interactive control outside the row button.
      Color.clear.frame(width: 20, height: 17)
        .anchorPreference(key: MergeControlBoundsKey.self, value: .bounds) { $0 }
        .accessibilityHidden(true)
      Text(verbatim: "#\(pullRequest.number)").font(.caption.monospacedDigit()).fixedSize()
      if let position = pullRequest.stackPosition, let size = pullRequest.stackSize, size > 1 {
        StackBadge(position: position, size: size).fixedSize()
      }
      if isPinned {
        Image(systemName: "pin.fill")
          .font(.caption2)
          .nativeHelp("Pinned")
          .accessibilityLabel("Pinned pull request")
      }
    }
  }

  private var author: some View {
    HStack(spacing: 0) {
      AvatarView(url: pullRequest.authorAvatarURL)
      // A fragment such as "m…" says less than the avatar alone.
      ViewThatFits(in: .horizontal) {
        Text(pullRequest.author).lineLimit(1).padding(.leading, 4)
        Color.clear.frame(width: 0, height: 0)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(pullRequest.author)
    .nativeHelp(pullRequest.author)
  }

  private var lineChanges: some View {
    HStack(spacing: 4) {
      Text(verbatim: "+\(pullRequest.additions)").foregroundStyle(.green)
      Text(verbatim: "−\(pullRequest.deletions)").foregroundStyle(.red)
    }
    .fontDesign(.monospaced)
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(pullRequest.additions) additions, \(pullRequest.deletions) deletions")
    .nativeHelp("Lines changed")
  }

  @ViewBuilder private var checkIcon: some View {
    switch pullRequest.checksState {
    case .success: StatusIcon(icon: .checksPassed, text: "Checks passed", color: .statusGreen)
    case .failure: StatusIcon(icon: .checksFailed, text: "Checks failed", color: .red)
    case .pending: StatusIcon(icon: .checksRunning, text: "Checks running", color: .orange)
    case .neutral:
      Image(systemName: "minus.circle").resizable().scaledToFit()
        .nativeHelp("Checks neutral").accessibilityLabel("Checks neutral")
    case .unknown: Color.clear
    }
  }

  @ViewBuilder private var reviewIcon: some View {
    switch pullRequest.reviewDecision {
    case "APPROVED": StatusIcon(icon: .approved, text: "Approved", color: .statusGreen)
    case "CHANGES_REQUESTED":
      StatusIcon(icon: .changesRequested, text: "Changes requested", color: .red)
    case "REVIEW_REQUIRED": PendingReviewIcon()
    default: Color.clear
    }
  }
}

private struct MergeControlBoundsKey: PreferenceKey {
  static var defaultValue: Anchor<CGRect>? = nil
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = nextValue() ?? value
  }
}

private struct ElapsedTimeLabel: View {
  let date: Date
  let event: String

  var body: some View {
    // Aligned to the date itself, so each tick lands exactly when another minute has elapsed.
    TimelineView(.periodic(from: date, by: 60)) { context in
      let elapsed = ElapsedTime(from: date, to: context.date)
      Text(verbatim: elapsed.abbreviated)
        .accessibilityLabel(Text(verbatim: "\(event) \(elapsed.spoken) ago"))
    }
    .font(.caption.monospacedDigit())
    .fixedSize()
    .nativeHelp("\(event) \(date.formatted(date: .abbreviated, time: .shortened))")
  }
}

private struct AttentionReasonIcon: View {
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
    Image(systemName: symbol)
      .resizable()
      .scaledToFit()
      .frame(width: 11, height: 11)
      .foregroundStyle(color)
      .nativeHelp(summary.message)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Attention status: \(summary.message)")
  }
}

private struct PendingReviewIcon: View {
  var body: some View {
    Circle()
      .fill(.yellow)
      .frame(width: 11, height: 11)
      .nativeHelp("Review pending")
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

private struct StatusIcon: View {
  let icon: Octicon
  let text: String
  let color: Color

  var body: some View {
    OcticonImage(icon: icon, size: 11)
      .foregroundStyle(color)
      .nativeHelp(text)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(text)
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
    .padding(.horizontal, 5)
    .padding(.vertical, 2)
    .background(Color.primary.opacity(0.06), in: Capsule())
    .nativeHelp("Stacked pull request \(position) of \(size)")
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
  let refresh: () -> Void

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
        Button("Try Again", action: refresh)
          .help("Check your GitHub connection")
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct GitHubUnavailableView: View {
  @ObservedObject var store: AppStore
  let refresh: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label(store.refreshBlockedUntil == nil ? "Couldn’t refresh pull requests" : "Refresh paused",
        systemImage: "icloud.slash")
    } description: {
      Text(store.errorMessage ?? "Try refreshing again.")
        .textSelection(.enabled)
    } actions: {
      Button("Try Again", action: refresh)
        .help("Retry GitHub now")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
