# Contributing to Glance

Contributions are welcome. Keep changes focused, explain the user-facing reason for them, and follow the existing native macOS design.

For substantial behavior or interface changes, open a pull request with a short proposal before investing in a complete implementation. Bug fixes and small refinements can go directly to a pull request.

## Development setup

Glance requires macOS 14 or later and Xcode 16 or later.

```sh
git clone https://github.com/atchad/glance.git
cd glance
./scripts/build-app.sh
open dist/Glance.app
```

### Testing without disrupting your desktop

The full suite includes tests that open windows and change application focus. Run
those tests in a dedicated macOS VM or CI runner, not on a desktop being used for work.
On your working Mac, run the non-interactive subset instead:

```sh
swift test \
  --skip PanelWindowTests \
  --skip PullRequestBrowserTests.testLiveWebViewRetainsDraftScrollHistoryAndWindowAcrossCloseAndReopen
```

For local GUI testing on Apple silicon, [Tart](https://tart.run/quick-start/) can run
a macOS VM with its own logged-in desktop even when started with `tart run --no-graphics`.
Run the tests through SSH in the guest; keep source and build output on the guest's
local disk, and do not share your personal Glance profile or GitHub credentials.
A separate macOS desktop Space does not isolate focus or keyboard input.

### Full checks in an isolated macOS desktop

Run the same core checks used by CI inside the VM or dedicated runner:

```sh
zsh -n scripts/*.sh
swift test
zsh scripts/test-keybindings.sh
zsh scripts/test-panel-window.sh
zsh scripts/test-repository-color-window.sh
zsh scripts/test-pr-browser.sh
./scripts/build-app.sh release
zsh scripts/verify-app-signing.sh dist/Glance.app
lipo dist/Glance.app/Contents/MacOS/Glance -verify_arch arm64 x86_64
```

Local application bundles receive an ad-hoc signature without hardened runtime when a Developer ID identity is not available. This allows macOS to load bundled frameworks that have no Team ID. Certificate-signed builds keep hardened runtime and timestamping. You do not need the maintainer's signing or notarization credentials to contribute.

`test-panel-window.sh` exercises the actual AppKit menu-bar button, its popover, and the separate floating panel, including surface switching, resize notifications, reopening, and saved-frame restoration. It requires a macOS GUI session but not XCTest; `GLANCE_SDK_PATH` selects a specific installed SDK if needed.

`test-pr-browser.sh` exercises a real retained WebKit page with an offline HTML fixture,
including scroll position, a comment draft, expanded discussions, navigation, close/reopen,
reload cancellation, and cleanup. It requires a macOS GUI session but does not contact
GitHub or use your browser sign-in. `GLANCE_SDK_PATH` selects a specific installed SDK.

For changes to hover captions, run `zsh scripts/test-tooltip-hover.sh` in a macOS GUI session. It builds for release, opens the actual floating dashboard with fixture rows, and uses Vision to verify rendered tooltips across successive hovers, reopening, and refreshing. `GLANCE_TOOLTIP_CONFIGURATION=debug` selects a debug build. Leave the mouse and keyboard idle during the check; loss of focus or pointer movement is reported separately from a tooltip failure. It restores the previous pointer position and active app afterwards and never uses your GitHub account or Glance profile.

`test-repository-color-window.sh` opens the real Settings window to verify repository color deep links, including repeated links to the same repository. It requires a macOS GUI session, uses isolated fixture preferences, and never accesses your GitHub account. `GLANCE_SDK_PATH` selects a specific installed SDK if needed.

## Pull requests

- Describe the problem and the behavior your change introduces.
- Add or update tests when behavior changes.
- Include before-and-after screenshots for visible interface changes.
- Update documentation when setup, operation, or user-facing behavior changes.
- Do not commit build products, credentials, tokens, signing exports, or personal data.
- Keep unrelated formatting and refactoring out of the change.

All required GitHub Actions checks must pass before a pull request can be merged.

## Security reports

Do not disclose a suspected vulnerability in a pull request. Follow [the security policy](SECURITY.md) instead.

## Dependency updates

Verified Dependabot pull requests are enrolled in GitHub auto-merge for all update types, including major updates. The workflow does not check out or run pull-request code with its write token. Main-branch rules still require up-to-date passing CI; failures or conflicts prevent merging. No human approval is currently required by the ruleset.
