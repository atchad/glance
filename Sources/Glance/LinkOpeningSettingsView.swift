import AppKit
import SwiftUI

struct LinkOpeningSettingsView: View {
  @ObservedObject var store: AppStore
  @ObservedObject var session: GitHubWebSession
  @State private var applications: [LinkApplication] = []
  @State private var confirmingLogOut = false

  var body: some View {
    SettingsGroup {
      LabeledContent("Open links with") {
        LinkApplicationPicker(selection: $store.preferences.linkOpening, applications: applications)
          .fixedSize(horizontal: true, vertical: false)
      }
      if store.preferences.linkOpening == .glance {
        LabeledContent("GitHub website") {
          HStack(spacing: 10) {
            switch session.state {
            case .checking:
              ProgressView().controlSize(.small)
              Text("Checking sign-in…").foregroundStyle(.secondary)
            case .signedOut:
              Text("Not logged in").foregroundStyle(.secondary)
              Button("Log in…") { store.showGitHubWebLogin() }
            case .signedIn(let login):
              Text(login.map { "@\($0)" } ?? "Logged in").foregroundStyle(.secondary)
              Button("Log out…") { confirmingLogOut = true }
            }
          }.disabled(session.isSigningOut)
        }
      }
      if let message = store.linkOpeningErrorMessage {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(.orange)
      }
    } header: {
      HStack {
        Text("Links")
        SettingsHelpButton(title: "Opening links", message: store.preferences.linkOpening == .glance
          ? "Glance keeps pull request pages open in the background so you can return to your place. Sign in with the same GitHub account as the CLI. This website session is separate from GitHub CLI and your other browsers."
          : "Pull requests, checks, and notification links open in your chosen application. Glance stops preloading new pages. Existing Glance pages stay open until their pull request leaves the dashboard or you quit.")
      }
    }
    .onAppear {
      applications = LinkApplications.recommended()
      session.refresh()
    }
    .alert("Log out of GitHub in Glance?", isPresented: $confirmingLogOut) {
      Button("Cancel", role: .cancel) {}
      Button("Log out", role: .destructive) { Task { await store.logOutOfGitHubWebSession() } }
    } message: {
      Text("This closes all Glance browser windows and discards unfinished comments, review edits, and scroll positions. GitHub website data in Glance is cleared. GitHub CLI and other browsers are not affected.")
    }
  }
}

/// A native popup supports a command item without storing "Choose application" as a
/// preference. Canceling the disk picker leaves both the preference and popup unchanged.
struct LinkApplicationPicker: NSViewRepresentable {
  @Binding var selection: LinkOpeningPreference
  let applications: [LinkApplication]
  var chooseApplication: @MainActor (NSWindow?, @escaping (LinkApplication?) -> Void) -> Void = {
    LinkApplications.choose(for: $0, completion: $1)
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = NSPopUpButton(frame: .zero, pullsDown: false)
    button.alignment = .right
    button.isBordered = false
    button.target = context.coordinator
    button.action = #selector(Coordinator.selected(_:))
    button.setAccessibilityLabel("Open links with")
    return button
  }

  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.selection = $selection
    context.coordinator.chooseApplication = chooseApplication
    context.coordinator.update(button, applications: applications, selection: selection)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> NSSize? {
    // AppKit's default intrinsic width accommodates the longest menu item, even
    // when a short application name is selected. Size the displayed value instead.
    let item = nsView.selectedItem
    let font = nsView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let titleWidth = ((item?.title ?? "") as NSString).size(withAttributes: [.font: font]).width
    let imageWidth: CGFloat = item?.image == nil ? 0 : 22
    return NSSize(width: ceil(titleWidth + imageWidth + 32), height: nsView.intrinsicContentSize.height)
  }

  @MainActor
  final class Coordinator: NSObject {
    var selection: Binding<LinkOpeningPreference>?
    var chooseApplication: (@MainActor (NSWindow?, @escaping (LinkApplication?) -> Void) -> Void)?
    private var choices: [LinkOpeningPreference] = []

    func update(_ button: NSPopUpButton, applications: [LinkApplication], selection: LinkOpeningPreference) {
      var choices: [LinkOpeningPreference] = [.defaultBrowser, .glance]
      choices += applications.filter { !$0.isGlance }.map { .application($0) }
      if case .application = selection, !choices.contains(selection) { choices.append(selection) }
      if self.choices != choices {
        self.choices = choices
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, choice) in choices.enumerated() {
          if index == 2 { menu.addItem(.separator()) }
          let item = NSMenuItem()
          item.tag = index
          switch choice {
          case .defaultBrowser: item.title = "Default browser"
          case .glance: item.title = "Glance"
          case .application(let application):
            item.title = application.name
            let icon = NSWorkspace.shared.icon(forFile: application.url.path).copy() as? NSImage
            icon?.size = NSSize(width: 16, height: 16)
            item.image = icon
          }
          menu.addItem(item)
        }
        menu.addItem(.separator())
        let choose = NSMenuItem(title: "Choose application…", action: nil, keyEquivalent: "")
        choose.tag = -1
        menu.addItem(choose)
        button.menu = menu
      }
      if let index = choices.firstIndex(of: selection) { button.selectItem(withTag: index) }
    }

    @objc func selected(_ button: NSPopUpButton) {
      guard let selection, let tag = button.selectedItem?.tag else { return }
      if tag == -1 {
        let previous = selection.wrappedValue
        if let index = choices.firstIndex(of: previous) { button.selectItem(withTag: index) }
        chooseApplication?(button.window) { [weak self, weak button] application in
          guard let self, let button, let application else { return }
          let choice: LinkOpeningPreference = application.isGlance ? .glance : .application(application)
          self.selection?.wrappedValue = choice
          self.update(button, applications: self.choices.compactMap {
            if case .application(let app) = $0 { return app }
            return nil
          }, selection: choice)
        }
      } else if choices.indices.contains(tag) { selection.wrappedValue = choices[tag] }
    }
  }
}
