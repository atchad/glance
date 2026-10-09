import AppKit

@main
struct BrowserCheckRunner {
  @MainActor
  static func main() {
    do {
      let checks = try PullRequestBrowserChecks.run()
      print("Passed \(checks) persistent PR browser checks.")
    } catch {
      fputs("PR browser checks failed: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }
}
