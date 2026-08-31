import SwiftUI

struct GlanceSettingsView: View {
  @ObservedObject var store: AppStore
  @ObservedObject var panel: FloatingPanelController

  var body: some View {
    TabView {
      GeneralSettingsView(store: store, panel: panel)
        .tabItem { Label("General", systemImage: "gearshape") }
      SectionSettingsView(store: store)
        .tabItem { Label("Sections", systemImage: "list.bullet") }
    }
    .frame(minWidth: 500, idealWidth: 520, minHeight: 420, idealHeight: 465)
  }
}

private struct GeneralSettingsView: View {
  @ObservedObject var store: AppStore
  @ObservedObject var panel: FloatingPanelController
  @State private var showingRepositoryPicker = false

  var body: some View {
    Form {
      Section("Account") {
        LabeledContent(
          "GitHub account", value: store.viewerLogin.map { "@\($0)" } ?? "Not connected")
        HStack {
          Text("Uses GitHub CLI authentication")
            .foregroundStyle(.secondary)
          Spacer()
          Link("Setup…", destination: URL(string: "https://cli.github.com/")!)
          Button("Check Connection") { store.refresh() }
            .help("Check your GitHub CLI sign-in")
        }
      }

      Section("Panel") {
        Toggle(
          "Open at login",
          isOn: Binding(
            get: { store.preferences.openAtLogin },
            set: { store.setOpenAtLogin($0) }
          ))
        if let message = store.loginItemErrorMessage {
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }
        Toggle(
          "Keep above other windows",
          isOn: Binding(
            get: { store.preferences.panelLevel == .floating },
            set: {
              store.preferences.panelLevel = $0 ? .floating : .desktop
              panel.applyLevel()
            }
          ))
        Toggle("Open when Glance starts", isOn: $store.preferences.openPanelAtLaunch)
      }

      Section("Menu Bar") {
        Picker("Count", selection: $store.preferences.menuBarCountMode) {
          ForEach(MenuBarCountMode.allCases) { mode in Text(mode.title).tag(mode) }
        }
      }

      Section("Notifications") {
        Toggle(
          "New review requests",
          isOn: Binding(
            get: { store.preferences.notificationsEnabled },
            set: { store.setNotificationsEnabled($0) }
          ))
        if store.preferences.notificationsEnabled {
          if let message = store.notificationAuthorizationMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
      }

      Section("Repositories") {
        Text("All repositories are included by default.")
          .font(.caption)
          .foregroundStyle(.secondary)
        LabeledContent("Visible repositories") {
          Button("Choose Repositories…") { showingRepositoryPicker = true }
            .help("Choose which repositories appear in Glance")
        }
        Text(repositorySummary)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("PR Rows") {
        Toggle("Author", isOn: $store.preferences.showAuthor)
        Toggle("Time", isOn: $store.preferences.showUpdatedAt)
        if store.preferences.showUpdatedAt {
          Picker("Time represents", selection: $store.preferences.timeDisplayMode) {
            ForEach(TimeDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
          }
        }
        Picker("Status layout", selection: $store.preferences.statusDisplayMode) {
          ForEach(StatusDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
        }
        Toggle("Review status", isOn: $store.preferences.showReviewStatus)
        Toggle("Check status", isOn: $store.preferences.showCheckStatus)
        Toggle(
          "Command-click removes a PR until it changes",
          isOn: $store.preferences.commandClickDismisses)
      }

      Section("Refresh") {
        Picker("Check for updates", selection: $store.preferences.refreshInterval) {
          Text("Every 15 seconds").tag(TimeInterval(15))
          Text("Every 30 seconds").tag(TimeInterval(30))
          Text("Every minute").tag(TimeInterval(60))
          Text("Every 2 minutes").tag(TimeInterval(120))
          Text("Every 5 minutes").tag(TimeInterval(300))
          Text("Every 10 minutes").tag(TimeInterval(600))
          Text("Every 15 minutes").tag(TimeInterval(900))
        }
      }
    }
    .formStyle(.grouped)
    .toggleStyle(GlanceSwitchToggleStyle())
    .contentMargins(.horizontal, 4, for: .scrollContent)
    .contentMargins(.vertical, 8, for: .scrollContent)
    .sheet(isPresented: $showingRepositoryPicker) {
      RepositoryNotificationPicker(store: store)
    }
  }

  private var repositorySummary: String {
    let excluded = store.preferences.excludedRepositories.count
    if excluded == 0 { return "Every repository is visible." }
    return
      "\(excluded) \(excluded == 1 ? "repository is" : "repositories are") excluded from Glance."
  }
}

private struct GlanceSwitchToggleStyle: ToggleStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(spacing: 12) {
        configuration.label
        Spacer(minLength: 12)
        Capsule(style: .continuous)
          .fill(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.28))
          .frame(width: 36, height: 20)
          .overlay(alignment: configuration.isOn ? .trailing : .leading) {
            Circle()
              .fill(.white)
              .frame(width: 16, height: 16)
              .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
              .padding(2)
          }
          .overlay {
            Capsule(style: .continuous)
              .stroke(.primary.opacity(configuration.isOn ? 0.08 : 0.16), lineWidth: 0.5)
          }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.5)
    .animation(.easeOut(duration: 0.14), value: configuration.isOn)
    .accessibilityValue(configuration.isOn ? "On" : "Off")
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
          Text("Visible Repositories").font(.headline)
          Text("Unchecked repositories are removed from Glance and its cache.")
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
      .listStyle(.inset)

      Divider()

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
      .padding(12)

      validationMessage
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
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
}
