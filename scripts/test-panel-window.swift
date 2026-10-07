import AppKit

@main
struct PanelWindowTestRunner {
  @MainActor
  static func main() {
    do {
      print("Passed \(try PanelWindowChecks.run()) native panel checks.")
    } catch {
      fputs("FAILED: \(error.localizedDescription)\n", stderr)
      exit(EXIT_FAILURE)
    }
  }
}
