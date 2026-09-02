import Foundation

enum GitHubError: LocalizedError {
  case ghUnavailable
  case notAuthenticated(String)
  case invalidResponse
  case api(String)

  var errorDescription: String? {
    switch self {
    case .ghUnavailable:
      "GitHub CLI was not found. Install gh and run ‘gh auth login’."
    case .notAuthenticated(let detail):
      detail.isEmpty ? "Run ‘gh auth login’ to connect Glance to GitHub." : detail
    case .invalidResponse:
      "GitHub returned an unreadable response."
    case .api(let message):
      message
    }
  }
}

enum QueryValidationError: LocalizedError {
  case missingPullRequestFilter
  case unmatchedQuote
  case rejected(String)

  var errorDescription: String? {
    switch self {
    case .missingPullRequestFilter: "Add “is:pr” so this section only contains pull requests."
    case .unmatchedQuote: "The search contains an unmatched quotation mark."
    case .rejected(let message): message
    }
  }
}

struct GitHubClient {
  private let endpoint = URL(string: "https://api.github.com/graphql")!

  func fetchAccessibleRepositories() async throws -> [String] {
    let token = try await tokenFromGitHubCLI()
    var page = 1
    var repositories: [String] = []

    while true {
      var components = URLComponents(string: "https://api.github.com/user/repos")!
      components.queryItems = [
        URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
        URLQueryItem(name: "visibility", value: "all"),
        URLQueryItem(name: "sort", value: "full_name"),
        URLQueryItem(name: "direction", value: "asc"),
        URLQueryItem(name: "per_page", value: "100"),
        URLQueryItem(name: "page", value: String(page)),
      ]
      guard let url = components.url else { throw GitHubError.invalidResponse }
      var request = URLRequest(url: url)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      request.setValue("Glance/0.1", forHTTPHeaderField: "User-Agent")

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
      guard (200..<300).contains(http.statusCode) else {
        let message =
          (try? JSONDecoder().decode(RESTError.self, from: data).message)
          ?? "GitHub could not load your repositories."
        throw GitHubError.api(message)
      }

      let batch = try JSONDecoder().decode([RESTRepository].self, from: data)
      repositories.append(contentsOf: batch.map(\.fullName))
      guard batch.count == 100 else { break }
      page += 1
    }

    return Array(Set(repositories)).sorted {
      $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }
  }

  func fetchAll(sections: [PRSection]) async throws -> (
    viewer: String, snapshots: [SectionSnapshot]
  ) {
    let token = try await tokenFromGitHubCLI()
    return try await withThrowingTaskGroup(of: (Int, String, SectionSnapshot).self) { group in
      for (index, section) in sections.enumerated() {
        group.addTask {
          let result = try await fetch(section: section, token: token)
          return (
            index, result.viewer, SectionSnapshot(id: section.id, pullRequests: result.pullRequests)
          )
        }
      }

      var collected: [(Int, String, SectionSnapshot)] = []
      for try await result in group { collected.append(result) }
      collected.sort { $0.0 < $1.0 }
      return (collected.first?.1 ?? "", collected.map(\.2))
    }
  }

  func validateSearchQuery(_ query: String) async throws {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
    guard tokens.contains(where: { $0.lowercased() == "is:pr" }) else {
      throw QueryValidationError.missingPullRequestFilter
    }
    var unescapedQuoteCount = 0
    var escaping = false
    for character in trimmed {
      if character == "\\" {
        escaping.toggle()
        continue
      }
      if character == "\"", !escaping { unescapedQuoteCount += 1 }
      escaping = false
    }
    guard unescapedQuoteCount.isMultiple(of: 2) else { throw QueryValidationError.unmatchedQuote }

    let token = try await tokenFromGitHubCLI()
    var components = URLComponents(string: "https://api.github.com/search/issues")!
    components.queryItems = [
      URLQueryItem(name: "q", value: trimmed), URLQueryItem(name: "per_page", value: "1"),
    ]
    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Glance/0.1", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let message =
        (try? JSONDecoder().decode(RESTError.self, from: data).message)
        ?? "GitHub rejected this search."
      throw QueryValidationError.rejected(message)
    }
  }

  private func fetch(section: PRSection, token: String) async throws -> (
    viewer: String, pullRequests: [PullRequest]
  ) {
    var viewer = ""
    var pullRequests: [PullRequest] = []
    var cursor: String?

    repeat {
      let page = try await fetchPage(section: section, token: token, cursor: cursor)
      viewer = page.viewer
      pullRequests.append(contentsOf: page.pullRequests)
      cursor = page.nextCursor
    } while cursor != nil

    return (viewer, pullRequests)
  }

  private func fetchPage(
    section: PRSection,
    token: String,
    cursor: String?
  ) async throws -> (viewer: String, pullRequests: [PullRequest], nextCursor: String?) {
    let query = """
      query GlanceSection($query: String!, $cursor: String) {
        viewer { login }
        search(query: $query, type: ISSUE, first: 50, after: $cursor) {
          pageInfo { hasNextPage endCursor }
          nodes {
            ... on PullRequest {
              id number title url headRefName headRefOid createdAt updatedAt isDraft
              additions deletions reviewDecision
              stack { size }
              stackEntry { position }
              author { login avatarUrl }
              repository { nameWithOwner }
              labels(first: 10) { nodes { name } }
              reviewRequests(first: 10) {
                nodes {
                  requestedReviewer {
                    ... on User { login }
                    ... on Team { name }
                  }
                }
              }
              reviews(last: 100) {
                nodes {
                  author { login }
                  state
                  submittedAt
                  commit { oid }
                }
              }
              timelineItems(last: 50, itemTypes: [REVIEW_REQUESTED_EVENT]) {
                nodes {
                  ... on ReviewRequestedEvent {
                    createdAt
                    requestedReviewer {
                      ... on User { login }
                      ... on Team { name }
                    }
                  }
                }
              }
              commits(last: 1) {
                nodes { commit { statusCheckRollup { state } } }
              }
            }
          }
        }
      }
      """

    let payload = GraphQLRequest(
      query: query,
      variables: GraphQLVariables(query: section.query, cursor: cursor)
    )
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Glance/0.1", forHTTPHeaderField: "User-Agent")
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      throw GitHubError.api("GitHub request failed with status \(http.statusCode).")
    }

    let decoded = try JSONDecoder.github.decode(GraphQLResponse.self, from: data)
    if let message = decoded.errors?.first?.message { throw GitHubError.api(message) }
    guard let graph = decoded.data else { throw GitHubError.invalidResponse }
    let pullRequests = graph.search.nodes.compactMap {
      $0?.rawPullRequest?.model(viewer: graph.viewer.login)
    }
    let nextCursor = graph.search.pageInfo.hasNextPage ? graph.search.pageInfo.endCursor : nil
    return (graph.viewer.login, pullRequests, nextCursor)
  }

  private func tokenFromGitHubCLI() async throws -> String {
    try await Task.detached(priority: .userInitiated) {
      let process = Process()
      let output = Pipe()
      let errors = Pipe()
      let candidates = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
      ]
      guard
        let executable = candidates.first(where: {
          FileManager.default.isExecutableFile(atPath: $0)
        })
      else {
        throw GitHubError.ghUnavailable
      }
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = ["auth", "token"]
      process.standardOutput = output
      process.standardError = errors
      do { try process.run() } catch { throw GitHubError.ghUnavailable }
      process.waitUntilExit()
      let token =
        String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let detail =
        String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard process.terminationStatus == 0, !token.isEmpty else {
        throw GitHubError.notAuthenticated(detail)
      }
      return token
    }.value
  }
}

private struct GraphQLRequest: Encodable {
  let query: String
  let variables: GraphQLVariables
}

private struct GraphQLVariables: Encodable {
  let query: String
  let cursor: String?
}

private struct RESTError: Decodable { let message: String }
private struct RESTRepository: Decodable {
  let fullName: String

  private enum CodingKeys: String, CodingKey {
    case fullName = "full_name"
  }
}

private struct GraphQLResponse: Decodable {
  let data: GraphData?
  let errors: [GraphError]?
}

private struct GraphError: Decodable { let message: String }
private struct GraphData: Decodable {
  let viewer: Viewer
  let search: SearchResult
}
private struct Viewer: Decodable { let login: String }
private struct SearchResult: Decodable {
  struct PageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
  }

  let nodes: [PRNode?]
  let pageInfo: PageInfo
}

private enum PRNode: Decodable {
  case pullRequest(RawPullRequest)

  var rawPullRequest: RawPullRequest? {
    if case .pullRequest(let value) = self { return value }
    return nil
  }

  init(from decoder: Decoder) throws {
    let raw = try RawPullRequest(from: decoder)
    self = .pullRequest(raw)
  }
}

private struct RawPullRequest: Decodable {
  struct Author: Decodable {
    let login: String
    let avatarUrl: URL?
  }
  struct Repository: Decodable { let nameWithOwner: String }
  struct LabelConnection: Decodable { let nodes: [Label] }
  struct Label: Decodable { let name: String }
  struct ReviewRequestConnection: Decodable { let nodes: [ReviewNode] }
  struct ReviewNode: Decodable { let requestedReviewer: Reviewer? }
  struct Reviewer: Decodable {
    let login: String?
    let name: String?
  }
  struct ReviewEventConnection: Decodable { let nodes: [ReviewEvent] }
  struct ReviewEvent: Decodable {
    let createdAt: Date
    let requestedReviewer: Reviewer?
  }
  struct ReviewConnection: Decodable { let nodes: [Review] }
  struct Review: Decodable {
    let author: Author?
    let state: String
    let submittedAt: Date?
    let commit: ReviewCommit?
  }
  struct ReviewCommit: Decodable { let oid: String }
  struct CommitConnection: Decodable { let nodes: [CommitNode] }
  struct CommitNode: Decodable { let commit: Commit }
  struct Commit: Decodable { let statusCheckRollup: Rollup? }
  struct Rollup: Decodable { let state: String }
  struct Stack: Decodable { let size: Int }
  struct StackEntry: Decodable { let position: Int }

  let id: String
  let number: Int
  let title: String
  let url: URL
  let headRefName: String
  let headRefOid: String
  let createdAt: Date
  let updatedAt: Date
  let isDraft: Bool
  let additions: Int
  let deletions: Int
  let reviewDecision: String?
  let stack: Stack?
  let stackEntry: StackEntry?
  let author: Author?
  let repository: Repository
  let labels: LabelConnection
  let reviewRequests: ReviewRequestConnection
  let reviews: ReviewConnection
  let timelineItems: ReviewEventConnection
  let commits: CommitConnection

  func model(viewer: String) -> PullRequest {
    let state = commits.nodes.last?.commit.statusCheckRollup?.state
    let checks: PullRequest.CheckState =
      switch state {
      case "SUCCESS": .success
      case "FAILURE", "ERROR": .failure
      case "PENDING", "EXPECTED": .pending
      case "NEUTRAL": .neutral
      default: .unknown
      }
    let matchingRequest =
      timelineItems.nodes.last(where: { $0.requestedReviewer?.login == viewer })
      ?? timelineItems.nodes.last
    let viewerReview = reviews.nodes.last {
      $0.author?.login == viewer
        && ($0.state == "APPROVED" || $0.state == "CHANGES_REQUESTED" || $0.state == "DISMISSED")
    }
    let hasCurrentApprovalFromOtherReviewer = PullRequest.hasCurrentApprovalFromOtherReviewer(
      in: reviews.nodes.map {
        PullRequest.ReviewSummary(
          author: $0.author?.login, state: $0.state, headOID: $0.commit?.oid)
      },
      viewer: viewer,
      headOID: headRefOid)
    return PullRequest(
      id: id, number: number, repository: repository.nameWithOwner,
      title: title, author: author?.login ?? "ghost", authorAvatarURL: author?.avatarUrl,
      url: url, branch: headRefName, headRefOID: headRefOid, createdAt: createdAt,
      reviewRequestedAt: matchingRequest?.createdAt, updatedAt: updatedAt,
      isDraft: isDraft, reviewDecision: reviewDecision, checksState: checks,
      additions: additions, deletions: deletions, labels: labels.nodes.map(\.name),
      requestedReviewers: reviewRequests.nodes.compactMap {
        $0.requestedReviewer?.login ?? $0.requestedReviewer?.name
      },
      viewerReviewState: viewerReview?.state == "DISMISSED" ? "APPROVED" : viewerReview?.state,
      viewerReviewedHeadOID: viewerReview?.commit?.oid,
      viewerReviewSubmittedAt: viewerReview?.submittedAt,
      hasCurrentApprovalFromOtherReviewer: hasCurrentApprovalFromOtherReviewer,
      stackPosition: stackEntry?.position, stackSize: stack?.size
    )
  }
}

extension JSONDecoder {
  fileprivate static var github: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
