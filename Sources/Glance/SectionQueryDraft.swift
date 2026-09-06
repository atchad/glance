import Foundation

enum SectionQueryExample: String, CaseIterable, Identifiable {
  case assignedToMe, myNonDraftPRs, repositoryPRs

  var id: Self { self }

  var name: String {
    switch self {
    case .assignedToMe: "Assigned to me"
    case .myNonDraftPRs: "My non-draft PRs"
    case .repositoryPRs: "Repository PRs"
    }
  }

  var menuTitle: String {
    self == .repositoryPRs ? "Repository PRs (replace repository)" : name
  }

  var query: String {
    switch self {
    case .assignedToMe: "is:pr is:open assignee:@me"
    case .myNonDraftPRs: "is:pr is:open author:@me draft:false"
    case .repositoryPRs: "is:pr is:open repo:OWNER/REPOSITORY"
    }
  }
}

/// A new section's editable draft, independent of saved sections.
struct SectionQueryDraft {
  var name = ""
  var query = "is:pr is:open " {
    didSet { validation.reset() }
  }
  var validation = SearchQueryValidation()

  var requiresRepositoryReplacement: Bool {
    query.localizedCaseInsensitiveContains("OWNER/REPOSITORY")
  }

  var canAdd: Bool {
    validation.state == .valid && !requiresRepositoryReplacement
      && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  mutating func apply(_ example: SectionQueryExample) {
    name = example.name
    query = example.query
  }

  mutating func beginValidation() -> UUID? {
    guard !requiresRepositoryReplacement else { return nil }
    return validation.begin()
  }
}
