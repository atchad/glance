import Combine
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
  let updaterController: SPUStandardUpdaterController
  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var automaticallyChecksForUpdates = false
  @Published private(set) var automaticallyDownloadsUpdates = false
  private var cancellables: Set<AnyCancellable> = []

  init() {
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil)
    let updater = updaterController.updater
    canCheckForUpdates = updater.canCheckForUpdates
    automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates

    updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])
      .receive(on: RunLoop.main)
      .sink { [weak self] in self?.canCheckForUpdates = $0 }
      .store(in: &cancellables)
    updater.publisher(for: \.automaticallyChecksForUpdates, options: [.initial, .new])
      .receive(on: RunLoop.main)
      .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
      .store(in: &cancellables)
    updater.publisher(for: \.automaticallyDownloadsUpdates, options: [.initial, .new])
      .receive(on: RunLoop.main)
      .sink { [weak self] in self?.automaticallyDownloadsUpdates = $0 }
      .store(in: &cancellables)
  }

  func checkForUpdates() {
    updaterController.checkForUpdates(nil)
  }

  func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
    updaterController.updater.automaticallyChecksForUpdates = enabled
  }

  func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
    updaterController.updater.automaticallyDownloadsUpdates = enabled
  }
}
