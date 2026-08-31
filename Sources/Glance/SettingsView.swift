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
    .frame(width: 560, height: 465)
  }
}

private struct GeneralSettingsView: View {
  @ObservedObject var store: AppStore
  @ObservedObject var panel: FloatingPanelController
  @State private var repositoryToMute = ""

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
          Text("All repositories are included by default.")
            .font(.caption)
            .foregroundStyle(.secondary)
          if store.notificationRepositories.isEmpty {
            Text("Repositories appear here after the first successful refresh.")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            ForEach(store.notificationRepositories, id: \.self) { repository in
              Toggle(
                repository,
                isOn: Binding(
                  get: { store.notificationsEnabled(for: repository) },
                  set: { store.setNotificationsEnabled($0, for: repository) }
                ))
            }
            Text("Turning off a repository only silences notifications. Its PRs remain visible.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          HStack {
            TextField("owner/repository", text: $repositoryToMute)
              .textFieldStyle(.roundedBorder)
              .font(.system(.body, design: .monospaced))
            Button("Mute") {
              let repository = repositoryToMute.trimmingCharacters(in: .whitespacesAndNewlines)
              store.setNotificationsEnabled(false, for: repository)
              repositoryToMute = ""
            }
            .disabled(!validRepositoryName(repositoryToMute))
            .help("Mute notifications for this repository")
          }
          if let message = store.notificationAuthorizationMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
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
    .padding(.horizontal, 8)
  }

  private func validRepositoryName(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains(where: { $0.isWhitespace }) else { return false }
    let pieces = trimmed.split(separator: "/", omittingEmptySubsequences: false)
    return pieces.count == 2 && pieces.allSatisfy { !$0.isEmpty }
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
