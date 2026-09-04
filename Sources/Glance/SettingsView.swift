import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
  case general, reviews, github, sections, updates

  var id: Self { self }
  var title: String {
    switch self {
    case .general: "General"
    case .reviews: "Pull requests"
    case .github: "GitHub"
    case .sections: "Sections"
    case .updates: "Software Update"
    }
  }
  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .reviews: "arrow.triangle.branch"
    case .github: "chevron.left.forwardslash.chevron.right"
    case .sections: "list.bullet.rectangle"
    case .updates: "arrow.triangle.2.circlepath"
    }
  }
  var color: Color {
    switch self {
    case .general: Color(nsColor: .systemGray)
    case .reviews: Color(nsColor: .systemIndigo)
    case .github: Color(nsColor: .systemBlue)
    case .sections: Color(nsColor: .systemTeal)
    case .updates: Color(nsColor: .systemGreen)
    }
  }
}

private struct SettingsCategoryLabel: View {
  let category: SettingsCategory

  var body: some View {
    Label {
      Text(category.title)
    } icon: {
      ZStack {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(
            LinearGradient(
              colors: [category.color.opacity(0.72), category.color],
              startPoint: .top,
              endPoint: .bottom)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .stroke(.white.opacity(0.18), lineWidth: 0.5)
          }
        Image(systemName: category.symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
      }
      .frame(width: 22, height: 22)
      .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
    }
  }
}

struct GlanceSettingsView: View {
  @ObservedObject var store: AppStore
  @ObservedObject var panel: FloatingPanelController
  @ObservedObject var updates: UpdateController
  @State private var selection: SettingsCategory = .general
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List(SettingsCategory.allCases, selection: $selection) { category in
        SettingsCategoryLabel(category: category)
          .tag(category)
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
    } detail: {
      settingsPage
        .toolbar(removing: .sidebarToggle)
    }
    .onChange(of: columnVisibility) { _, visibility in
      if visibility != .all { columnVisibility = .all }
    }
    .frame(minWidth: 720, idealWidth: 800, minHeight: 540, idealHeight: 600)
  }

  @ViewBuilder private var settingsPage: some View {
    switch selection {
    case .general: GeneralSettingsPage(store: store, panel: panel)
    case .reviews: ReviewSettingsPage(store: store)
    case .github: GitHubSettingsPage(store: store)
    case .sections: SectionSettingsView(store: store)
    case .updates: UpdateSettingsPage(updates: updates)
    }
  }
}

private struct GeneralSettingsPage: View {
  @ObservedObject var store: AppStore
  @ObservedObject var panel: FloatingPanelController
  var body: some View {
    SettingsForm {
      Section {
        Toggle(
          "Launch Glance at login",
          isOn: Binding(
            get: { store.preferences.openAtLogin },
            set: { store.setOpenAtLogin($0) }))
          .help("Start Glance automatically when you sign in to your Mac.")
        if let message = store.loginItemErrorMessage {
          SettingsWarning(message: message)
        }
        Toggle("Open the panel when Glance starts", isOn: $store.preferences.openPanelAtLaunch)
          .help("Show the pull-request panel immediately after Glance launches.")
      } header: {
        Text("Startup")
      } footer: {
        Text("Glance stays in the menu bar unless you choose to open the panel.")
      }
      Section("Appearance") {
        Picker("Appearance", selection: $store.preferences.appearanceMode) {
          ForEach(AppearanceMode.allCases) { mode in Text(mode.title).tag(mode) }
        }
        .help("Use the system appearance, or always use light or dark mode in Glance.")
      }
      Section {
        Toggle(
          "Keep the panel above other windows",
          isOn: Binding(
            get: { store.preferences.panelLevel == .floating },
            set: {
              store.preferences.panelLevel = $0 ? .floating : .desktop
              panel.applyLevel()
            }))
          .help("Keep the detached panel in front of other windows while it is visible.")
      } header: {
        Text("Window")
      } footer: {
        Text("Keep the detached panel visible while you work in another app.")
      }
    }
  }
}

private struct UpdateSettingsPage: View {
  @ObservedObject var updates: UpdateController

  var body: some View {
    SettingsForm {
      Section("Software Updates") {
        Toggle(
          "Automatically check for updates",
          isOn: Binding(
            get: { updates.automaticallyChecksForUpdates },
            set: { updates.setAutomaticallyChecksForUpdates($0) }))
        Toggle(
          "Automatically download and install updates",
          isOn: Binding(
            get: { updates.automaticallyDownloadsUpdates },
            set: { updates.setAutomaticallyDownloadsUpdates($0) })
        )
        .disabled(!updates.automaticallyChecksForUpdates)
        Button("Check Now") { updates.checkForUpdates() }
          .disabled(!updates.canCheckForUpdates)
      }
      Section("Installed Version") {
        LabeledContent("Version", value: installedVersion)
      }
    }
  }

  private var installedVersion: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    switch (version, build) {
    case (.some(let version), .some(let build)): return "\(version) (\(build))"
    case (.some(let version), .none): return version
    default: return "Unknown"
    }
  }
}

private struct ReviewSettingsPage: View {
  @ObservedObject var store: AppStore
  var body: some View {
    SettingsForm {
      Section {
        Picker("Count", selection: $store.preferences.menuBarCountMode) {
          ForEach(MenuBarCountMode.allCases) { mode in Text(mode.title).tag(mode) }
        }
        .help("Choose what the number beside the menu-bar icon counts.")
        if store.preferences.menuBarCountMode == .awaitingReview {
          Toggle(
            "Include pull requests opened by me",
            isOn: $store.preferences.includeMyPullRequestsInMenuBarCount)
            .help("Include your own open pull requests in the menu-bar count.")
        }
      } header: {
        Text("Menu-bar count")
      } footer: {
        Text("Choose which pull requests contribute to the number beside the menu-bar icon.")
      }
      Section("Completed reviews") {
        Toggle(
          "Remove pull requests after I approve them",
          isOn: $store.preferences.removePullRequestsAfterApproval)
          .help("Hide a pull request after your approval, until it changes or you are asked to review it again.")
        Toggle(
          "Remove pull requests after another reviewer approves them",
          isOn: $store.preferences.removePullRequestsAfterOtherApproval)
          .help("Hide a pull request after another reviewer approves the current revision.")
        Toggle(
          "Show again when new changes are pushed",
          isOn: $store.preferences.showChangedPullRequestsAfterApproval
        )
        .disabled(!store.preferences.removePullRequestsAfterApproval)
        .help("Show an approved pull request again when its branch receives new commits.")
        Toggle(
          "Show again when my review is re-requested",
          isOn: $store.preferences.showRerequestedPullRequestsAfterApproval
        )
        .disabled(!store.preferences.removePullRequestsAfterApproval)
        .help("Show an approved pull request again when your review is requested again.")
      }
      Section("Row Details") {
        Toggle("Author", isOn: $store.preferences.showAuthor)
        Toggle("Time", isOn: $store.preferences.showUpdatedAt)
        if store.preferences.showUpdatedAt {
          Picker("Time represents", selection: $store.preferences.timeDisplayMode) {
            ForEach(TimeDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
          }
        }
        Toggle("Additions and deletions", isOn: $store.preferences.showLineChanges)
        Toggle("Attention reason", isOn: $store.preferences.showAttentionReason)
          .help("Show why each pull request needs attention or what it is waiting for.")
        Picker("Status layout", selection: $store.preferences.statusDisplayMode) {
          ForEach(StatusDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
        }
        Toggle("Review status", isOn: $store.preferences.showReviewStatus)
        Toggle("Check status", isOn: $store.preferences.showCheckStatus)
        Toggle(
          "Command-click to dismiss a pull request until it changes",
          isOn: $store.preferences.commandClickDismisses)
      }
      Section {
        Picker("Refresh pull requests", selection: $store.preferences.refreshInterval) {
          Text("Every 15 seconds").tag(TimeInterval(15))
          Text("Every 30 seconds").tag(TimeInterval(30))
          Text("Every minute").tag(TimeInterval(60))
          Text("Every 2 minutes").tag(TimeInterval(120))
          Text("Every 5 minutes").tag(TimeInterval(300))
          Text("Every 10 minutes").tag(TimeInterval(600))
          Text("Every 15 minutes").tag(TimeInterval(900))
        }
        .help("How often Glance asks GitHub for updated pull-request data.")
      } header: {
        Text("Refresh")
      } footer: {
        Text("Glance keeps the last successful results visible if GitHub is temporarily unavailable.")
      }
    }
  }
}

private struct GitHubSettingsPage: View {
  @ObservedObject var store: AppStore
  @State private var showingRepositoryPicker = false
  var body: some View {
    SettingsForm {
      Section("Account") {
        LabeledContent(
          "GitHub account", value: store.viewerLogin.map { "@\($0)" } ?? "Not connected")
        LabeledContent("Authentication") {
          HStack {
            Link("GitHub CLI Setup…", destination: URL(string: "https://cli.github.com/")!)
            Button("Check Connection") { store.refresh() }
          }
        }
      }
      Section {
        LabeledContent {
          Button("Manage repositories…") { showingRepositoryPicker = true }
            .help("Choose which repositories appear in Glance and can send notifications.")
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text("Visible repositories")
            Text(repositorySummary).font(.caption).foregroundStyle(.secondary)
          }
        }
      } header: {
        Text("Repositories")
      } footer: {
        Text("Excluded repositories are removed from the list, cache, and notifications.")
      }
      Section("Notifications") {
        Toggle(
          "Notify me about new review requests",
          isOn: Binding(
            get: { store.preferences.notificationsEnabled },
            set: { store.setNotificationsEnabled($0) }))
          .help("Send a native notification when a new pull request requests your review.")
        if store.preferences.notificationsEnabled,
          let message = store.notificationAuthorizationMessage
        {
          SettingsWarning(message: message)
        }
      }
    }
    .sheet(isPresented: $showingRepositoryPicker) {
      RepositoryNotificationPicker(store: store)
    }
  }
  private var repositorySummary: String {
    let excluded = store.preferences.excludedRepositories.count
    if excluded == 0 { return "Every repository is visible." }
    return "\(excluded) \(excluded == 1 ? "repository is" : "repositories are") excluded."
  }
}

private struct SettingsForm<Content: View>: View {
  @ViewBuilder let content: Content
  var body: some View {
    Form { content }
      .formStyle(.grouped)
      .toggleStyle(.switch)
      .contentMargins(.horizontal, 0, for: .scrollContent)
      .contentMargins(.top, -12, for: .scrollContent)
      .contentMargins(.bottom, 10, for: .scrollContent)
  }
}

private struct SettingsWarning: View {
  let message: String
  var body: some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.caption).foregroundStyle(.orange)
  }
}

private struct RepositoryNotificationPicker: View {
  @ObservedObject var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var selected: Set<String> = []
  @State private var initialized = false

  private var filteredRepositories: [String] {
    guard !search.isEmpty else { return store.accessibleRepositories }
    return store.accessibleRepositories.filter {
      $0.localizedCaseInsensitiveContains(search)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Visible repositories").font(.headline)
          Text("Unchecked repositories are removed from Glance, its cache, and notifications.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if !store.accessibleRepositories.isEmpty {
          Text("\(selected.count) of \(store.accessibleRepositories.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      .padding()

      Divider()

      if store.isLoadingRepositories {
        ProgressView("Loading repositories from GitHub…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = store.repositoryLoadError {
        ContentUnavailableView {
          Label("Couldn’t Load Repositories", systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button("Try Again") { Task { await store.loadAccessibleRepositories() } }
        }
      } else {
        VStack(spacing: 10) {
          TextField("Search repositories", text: $search)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
            .padding(.top, 12)
          List(filteredRepositories, id: \.self) { repository in
            Toggle(
              repository,
              isOn: Binding(
                get: { selected.contains(repository) },
                set: { enabled in
                  if enabled { selected.insert(repository) } else { selected.remove(repository) }
                }
              )
            )
            .toggleStyle(.checkbox)
          }
          .listStyle(.inset)
        }
      }

      Divider()

      HStack {
        Button("Select All") { selected = Set(store.accessibleRepositories) }
          .disabled(store.accessibleRepositories.isEmpty)
        Button("Deselect All") { selected.removeAll() }
          .disabled(store.accessibleRepositories.isEmpty)
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Done") {
          store.applyRepositorySelection(selected)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(store.accessibleRepositories.isEmpty || !initialized)
      }
      .padding()
    }
    .frame(width: 540, height: 560)
    .task {
      await store.loadAccessibleRepositories()
      initializeSelectionIfNeeded()
    }
    .onChange(of: store.accessibleRepositories) { _, _ in
      initializeSelectionIfNeeded()
    }
  }

  private func initializeSelectionIfNeeded() {
    guard !initialized, !store.accessibleRepositories.isEmpty else { return }
    selected = Set(store.accessibleRepositories)
      .subtracting(store.preferences.excludedRepositories)
    initialized = true
  }
}

private struct SectionSettingsView: View {
  private enum ValidationState: Equatable {
    case idle
    case validating
    case valid
    case invalid(String)
  }

  @ObservedObject var store: AppStore
  @State private var draftName = ""
  @State private var draftQuery = "is:pr is:open "
  @State private var validationState: ValidationState = .idle

  var body: some View {
    VStack(spacing: 0) {
      List {
        Section("Displayed in this order") {
          ForEach($store.preferences.sections) { $section in
            HStack(alignment: .center, spacing: 10) {
              VStack(alignment: .leading, spacing: 5) {
                TextField("Section name", text: $section.name)
                  .textFieldStyle(.plain)
                  .font(.body)
                TextField("GitHub search", text: $section.query)
                  .textFieldStyle(.plain)
                  .font(.system(.caption, design: .monospaced))
                  .foregroundStyle(.secondary)
                Picker("Sort", selection: $section.sortMode) {
                  ForEach(PRSortMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 170, alignment: .leading)
                .help("Choose how pull requests in this section are ordered.")
              }
              VStack(spacing: 2) {
                Button { moveSection(id: section.id, offset: -1) } label: {
                  Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(store.preferences.sections.first?.id == section.id)
                .help("Move section up")
                Button { moveSection(id: section.id, offset: 1) } label: {
                  Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(store.preferences.sections.last?.id == section.id)
                .help("Move section down")
              }
              Button {
                store.preferences.sections.removeAll { $0.id == section.id }
                store.refresh()
              } label: {
                Image(systemName: "minus.circle.fill")
              }
              .buttonStyle(.borderless)
              .foregroundStyle(.secondary)
              .help("Remove section")
            }
            .padding(.vertical, 5)
          }
        }
      }
      .listStyle(.inset)

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        Text("Add section")
          .font(.headline)
        HStack(spacing: 8) {
          TextField("Section name", text: $draftName)
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
          TextField("GitHub search", text: $draftQuery)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .onChange(of: draftQuery) { _, _ in validationState = .idle }
          Button {
            validationState = .validating
            Task {
              if let error = await store.validateSectionQuery(draftQuery) {
                validationState = .invalid(error)
              } else {
                validationState = .valid
              }
            }
          } label: {
            if validationState == .validating {
              ProgressView().controlSize(.small).frame(width: 48)
            } else {
              Text("Validate")
            }
          }
          .disabled(validationState == .validating)
          .help("Validate this search with GitHub")
          Button {
            guard !draftName.trimmingCharacters(in: .whitespaces).isEmpty,
              !draftQuery.trimmingCharacters(in: .whitespaces).isEmpty
            else { return }
            store.preferences.sections.append(PRSection(name: draftName, query: draftQuery))
            draftName = ""
            draftQuery = "is:pr is:open "
            validationState = .idle
            store.refresh()
          } label: {
            Image(systemName: "plus")
          }
          .buttonStyle(.bordered)
          .disabled(
            validationState != .valid
              || draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
          .help("Add section")
        }
        validationMessage
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(16)
      .background(.bar)
    }
  }

  @ViewBuilder
  private var validationMessage: some View {
    switch validationState {
    case .idle:
      Text("Validate a GitHub pull request search before adding it.")
        .font(.caption).foregroundStyle(.secondary)
    case .validating:
      Text("Checking with GitHub…")
        .font(.caption).foregroundStyle(.secondary)
    case .valid:
      Label("Valid search", systemImage: "checkmark.circle.fill")
        .font(.caption).foregroundStyle(.green)
    case .invalid(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(.caption).foregroundStyle(.red)
    }
  }

  private func moveSection(id: UUID, offset: Int) {
    guard let index = store.preferences.sections.firstIndex(where: { $0.id == id }) else { return }
    let destination = index + offset
    guard store.preferences.sections.indices.contains(destination) else { return }
    store.preferences.sections.swapAt(index, destination)
    store.refresh()
  }
}
