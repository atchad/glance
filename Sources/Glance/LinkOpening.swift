import AppKit
import UniformTypeIdentifiers

struct LinkApplication: Codable, Hashable {
  let url: URL
  let bundleIdentifier: String?

  init(url: URL, bundleIdentifier: String? = nil) {
    self.url = url.standardizedFileURL
    self.bundleIdentifier = bundleIdentifier ?? (url.isFileURL ? Bundle(url: url)?.bundleIdentifier : nil)
  }

  var name: String {
    let bundle = url.isFileURL ? Bundle(url: url) : nil
    return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? url.deletingPathExtension().lastPathComponent
  }

  var isGlance: Bool { bundleIdentifier == "app.glance.Glance" }
  var isValid: Bool { url.isFileURL && url.pathExtension.lowercased() == "app" }
}

enum LinkOpeningPreference: Codable, Hashable {
  case defaultBrowser
  case glance
  case application(LinkApplication)

  var isValid: Bool {
    if case .application(let application) = self { return application.isValid }
    return true
  }
}

@MainActor
enum LinkApplications {
  static func recommended() -> [LinkApplication] {
    recommendations(NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://github.com/")!))
  }

  static func recommendations(_ urls: [URL]) -> [LinkApplication] {
    var seen: Set<URL> = []
    return urls.map { LinkApplication(url: $0) }
      .filter { $0.isValid && !$0.isGlance && seen.insert($0.url).inserted }
      .sorted {
        let comparison = $0.name.localizedStandardCompare($1.name)
        return comparison == .orderedSame ? $0.url.path < $1.url.path : comparison == .orderedAscending
      }
  }

  static func resolve(_ application: LinkApplication) -> URL? {
    guard application.isValid, !application.isGlance else { return nil }
    if FileManager.default.fileExists(atPath: application.url.path),
      let bundle = Bundle(url: application.url),
      application.bundleIdentifier == nil || bundle.bundleIdentifier == application.bundleIdentifier
    { return application.url }
    return application.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
  }

  static func choose(for window: NSWindow?, completion: @escaping (LinkApplication?) -> Void) {
    let panel = NSOpenPanel()
    panel.title = "Choose an application to open links"
    panel.prompt = "Choose"
    panel.allowedContentTypes = [.applicationBundle]
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    let finish: (NSApplication.ModalResponse) -> Void = { response in
      completion(response == .OK ? panel.url.map { LinkApplication(url: $0) } : nil)
    }
    if let window { panel.beginSheetModal(for: window, completionHandler: finish) }
    else { finish(panel.runModal()) }
  }
}

/// The platform boundary is injectable so routing and fallback tests never launch browsers.
@MainActor
final class ExternalLinkOpener {
  private let resolve: @MainActor (LinkApplication) -> URL?
  private let openDefault: @MainActor (URL) -> Bool
  private let openApplication: @MainActor (URL, URL) async throws -> Void

  init(
    resolve: @escaping @MainActor (LinkApplication) -> URL? = { LinkApplications.resolve($0) },
    openDefault: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
    openApplication: @escaping @MainActor (URL, URL) async throws -> Void = { url, application in
      _ = try await NSWorkspace.shared.open([url], withApplicationAt: application,
        configuration: NSWorkspace.OpenConfiguration())
    }
  ) {
    self.resolve = resolve
    self.openDefault = openDefault
    self.openApplication = openApplication
  }

  /// Returns a user-facing warning only when the requested destination could not be used.
  func open(_ url: URL, preference: LinkOpeningPreference) async -> String? {
    if case .application(let application) = preference {
      if let resolved = resolve(application) {
        do { try await openApplication(url, resolved); return nil }
        catch { return fallback(url, reason: "Couldn’t open \(application.name): \(error.localizedDescription)") }
      }
      return fallback(url, reason: "\(application.name) is no longer available.")
    }
    return openDefault(url) ? nil : "Couldn’t open this link in your default browser."
  }

  private func fallback(_ url: URL, reason: String) -> String {
    reason + (openDefault(url) ? " Opened in your default browser instead." : " The default browser also couldn’t open the link.")
  }
}
