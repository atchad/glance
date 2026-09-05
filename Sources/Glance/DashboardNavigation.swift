import Foundation

/// The ordered, expanded search results used by both rendering and keyboard commands.
struct DashboardNavigation {
  struct RowID: Hashable {
    let sectionID: UUID
    let pullRequestID: String
  }

  struct Row {
    let id: RowID
    let pullRequest: PullRequest
  }

  private let sections: [(PRSection, [PullRequest])]
  let rows: [Row]

  init(sections: [(PRSection, [PullRequest])], query: String) {
    let filteredSections = sections.map { ($0.0, Self.filtered($0.1, query: query)) }
    self.sections = filteredSections
    rows = filteredSections.flatMap { section, items in
      section.isCollapsed ? [] : items.map {
        Row(id: RowID(sectionID: section.id, pullRequestID: $0.id), pullRequest: $0)
      }
    }
  }

  func items(in sectionID: UUID) -> [PullRequest] {
    sections.first { $0.0.id == sectionID }?.1 ?? []
  }

  func reconciled(_ selection: RowID?) -> RowID? {
    selection.flatMap { selected in rows.contains { $0.id == selected } ? selected : nil }
  }

  func pullRequest(for selection: RowID?) -> PullRequest? {
    rows.first { $0.id == selection }?.pullRequest
  }

  func moved(from selection: RowID?, by offset: Int) -> RowID? {
    guard !rows.isEmpty else { return nil }
    let current = rows.firstIndex { $0.id == selection } ?? (offset > 0 ? -1 : 0)
    return rows[((current + offset) % rows.count + rows.count) % rows.count].id
  }

  static func filtered(_ pullRequests: [PullRequest], query: String) -> [PullRequest] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return pullRequests }
    return pullRequests.filter {
      [$0.title, $0.repository, $0.author, $0.branch, "#\($0.number)", $0.attention.message]
        .joined(separator: " ").localizedCaseInsensitiveContains(query)
        || $0.labels.contains { $0.localizedCaseInsensitiveContains(query) }
    }
  }
}
