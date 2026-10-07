import AppKit
import Combine

/// A target is supplied by the active view, or explicitly by a row's button/menu.
/// Never retain a selected PR across a refresh or a focus change.
struct CommandTarget {
  var pullRequest: PullRequest?
  var section: PRSection?
  var navigate: ((GlanceAction) -> Void)?
  var focusSearch: (() -> Void)?
  var clearSearch: (() -> Void)?
  var showDetails: (() -> Void)?
  var close: (() -> Void)?
  var didOpen: (() -> Void)?
}

@MainActor
final class ApplicationCommands: ObservableObject {
  private let store: AppStore
  private let updates: UpdateController
  private weak var panel: FloatingPanelController?
  private weak var settings: SettingsWindowController?

  init(store: AppStore, updates: UpdateController) {
    self.store = store
    self.updates = updates
  }

  func configure(panel: FloatingPanelController, settings: SettingsWindowController) {
    self.panel = panel
    self.settings = settings
  }

  func showRepositoryColors(for repository: String) {
    panel?.hide()
    settings?.showRepositoryColors(for: repository)
  }

  func canPerform(_ action: GlanceAction, target: CommandTarget = CommandTarget()) -> Bool {
    switch action {
    case .nextPR, .previousPR, .firstPR, .lastPR: return target.navigate != nil
    case .search: return target.focusSearch != nil
    case .clearSearch: return target.clearSearch != nil
    case .details: return target.pullRequest != nil && target.showDetails != nil
    case .toggleSection: return target.section.map { section in store.preferences.sections.contains { $0.id == section.id } } ?? false
    case .openPR, .pin, .copyTitle, .copyURL, .copyBranch: return target.pullRequest != nil
    case .dismiss, .snoozeHour, .snoozeTomorrow, .snoozeWeek, .snoozeChanges:
      return target.pullRequest.map { !store.isSnoozed($0) } ?? false
    case .snoozeChecks:
      return target.pullRequest.map { $0.checksState == .pending && !store.isSnoozed($0) } ?? false
    case .wake: return target.pullRequest.map { store.isSnoozed($0) } ?? false
    case .undoDismissal: return store.dismissalToUndo != nil
    case .refresh: return !store.isRefreshing
    case .collapseAll, .expandAll: return !store.preferences.sections.isEmpty
    case .showPanel, .togglePanelLevel: return panel != nil
    case .hidePanel: return target.close != nil || panel?.isVisible == true
    case .settings: return settings != nil
    case .checkForUpdates: return updates.canCheckForUpdates
    case .quit: return true
    }
  }

  @discardableResult
  func perform(_ action: GlanceAction, target: CommandTarget = CommandTarget()) -> Bool {
    guard canPerform(action, target: target) else { return false }
    switch action {
    case .nextPR, .previousPR, .firstPR, .lastPR: target.navigate?(action)
    case .search: target.focusSearch?()
    case .clearSearch: target.clearSearch?()
    case .details: target.showDetails?()
    case .openPR:
      if let pr = target.pullRequest { store.open(pr); target.didOpen?() }
    case .dismiss: if let pr = target.pullRequest { store.dismiss(pr) }
    case .undoDismissal: store.undoDismissal()
    case .pin: if let pr = target.pullRequest { store.togglePin(pr) }
    case .copyTitle: if let pr = target.pullRequest { Self.copy(pr.title) }
    case .copyURL: if let pr = target.pullRequest { Self.copy(pr.url.absoluteString) }
    case .copyBranch: if let pr = target.pullRequest { Self.copy(pr.branch) }
    case .snoozeHour, .snoozeTomorrow, .snoozeWeek, .snoozeChanges, .snoozeChecks:
      guard let pr = target.pullRequest else { return false }
      let now = Date()
      let condition: SnoozeCondition
      switch action {
      case .snoozeHour: condition = .until(now.addingTimeInterval(3_600))
      case .snoozeTomorrow: condition = .until(Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400))
      case .snoozeWeek: condition = .until(Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(604_800))
      case .snoozeChecks: condition = .checksComplete(pr.revisionKey)
      default: condition = .revisionChanges(pr.revisionKey)
      }
      store.snooze(pr, condition: condition)
    case .wake: if let pr = target.pullRequest { store.unsnooze(pr) }
    case .toggleSection: if let section = target.section { store.toggleCollapse(section) }
    case .collapseAll, .expandAll:
      for index in store.preferences.sections.indices { store.preferences.sections[index].isCollapsed = action == .collapseAll }
    case .refresh: store.refresh()
    case .showPanel: target.close?(); panel?.show()
    case .hidePanel:
      if let close = target.close { close() } else { panel?.hide() }
    case .togglePanelLevel:
      store.preferences.panelLevel = store.preferences.panelLevel == .floating ? .desktop : .floating
      panel?.applyLevel()
    case .settings: target.close?(); panel?.hide(); settings?.show()
    case .checkForUpdates: updates.checkForUpdates()
    case .quit: NSApp.terminate(nil)
    }
    return true
  }

  nonisolated static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }
}
