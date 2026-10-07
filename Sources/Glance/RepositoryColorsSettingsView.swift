import SwiftUI

struct RepositoryColorsSettingsPage: View {
  @ObservedObject var store: AppStore
  @ObservedObject var navigation: SettingsNavigation
  @Environment(\.colorScheme) private var colorScheme
  @State private var search = ""

  private var repositories: [String] {
    store.colorRepositories.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Repo Colors").font(.title2.weight(.semibold))
        Text("New repositories cycle through ten colors. Your choices stay with each repository, even when it has no open pull requests.")
          .font(.callout).foregroundStyle(.secondary)
      }
      TextField("Search repositories", text: $search)
        .textFieldStyle(.roundedBorder)
      if store.colorRepositories.isEmpty {
        ContentUnavailableView("No repositories yet", systemImage: "paintpalette",
          description: Text("Repositories appear here after Glance loads their pull requests."))
      } else {
        ScrollViewReader { proxy in
          List(repositories, id: \.self, selection: $navigation.repository) { repository in
            HStack(spacing: 10) {
              Circle().fill(store.preferences.repositoryColor(for: repository)?
                .displayColor(for: colorScheme) ?? .secondary).frame(width: 12, height: 12)
                .accessibilityHidden(true)
              Text(verbatim: repository).lineLimit(1)
            }
            .tag(repository)
            .id(repository)
          }
          .listStyle(.inset)
          .frame(minHeight: 120, maxHeight: .infinity)
          .overlay {
            if repositories.isEmpty {
              Text("No matching repositories").foregroundStyle(.secondary)
            }
          }
          .onAppear { proxy.scrollTo(navigation.repository, anchor: .center) }
          .onChange(of: navigation.repositoryColorRequest) { _, _ in
            search = ""
            // Allow the filtered List to update before scrolling to a deep link.
            DispatchQueue.main.async { proxy.scrollTo(navigation.repository, anchor: .center) }
          }
        }
        Divider()
        if let repository = navigation.repository,
          let color = store.preferences.repositoryColor(for: repository)
        {
          colorEditor(repository: repository, color: color)
            .id(repository)
        } else {
          Text("Select a repository to change its color.").foregroundStyle(.secondary)
        }
      }
    }
    .padding(20)
    .onAppear {
      if navigation.repository == nil { navigation.repository = store.colorRepositories.first }
    }
  }

  private func colorEditor(repository: String, color: RepositoryColor) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(verbatim: repository)
        .font(.headline).foregroundStyle(color.displayColor(for: colorScheme))
        .textSelection(.enabled)
      Text("Default colors").font(.subheadline)
      HStack(spacing: 9) {
        ForEach(RepositoryColor.presets) { preset in
          Button {
            store.setRepositoryColor(preset.color, for: repository)
          } label: {
            Circle().fill(preset.color.displayColor(for: colorScheme))
              .frame(width: 28, height: 28)
              .overlay {
                if color == preset.color {
                  Image(systemName: "checkmark").font(.caption.weight(.bold))
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                }
              }
              .padding(3)
              .overlay {
                Circle().stroke(color == preset.color ? Color.primary : .clear, lineWidth: 1.5)
              }
          }
          .buttonStyle(.plain)
          .help(preset.name)
          .accessibilityLabel(preset.name)
          .accessibilityAddTraits(color == preset.color ? .isSelected : [])
        }
      }
      ColorPicker("Custom color", selection: Binding(
        get: { color.color },
        set: {
          if let chosen = RepositoryColor(color: $0) {
            store.setRepositoryColor(chosen, for: repository)
          }
        }), supportsOpacity: false)
        .help("Open the macOS color picker and use its color wheel to choose any color.")
      Text("Presets adapt to light and dark appearance. Custom colors use your exact choice.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(.bottom, 4)
  }
}

struct RepositoryNameLabel: View {
  let repository: String
  let color: RepositoryColor?
  var editColor: (() -> Void)? = nil
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Text(verbatim: repository)
      .foregroundStyle(color?.displayColor(for: colorScheme) ?? .secondary)
      .contextMenu {
        if let editColor {
          Button("Change Repo Color…", action: editColor)
        }
      }
  }
}
