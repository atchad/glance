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

Run the same core checks used by CI:

```sh
zsh -n scripts/*.sh
swift test
zsh scripts/test-keybindings.sh
zsh scripts/test-panel-window.sh
./scripts/build-app.sh release
zsh scripts/verify-app-signing.sh dist/Glance.app
lipo dist/Glance.app/Contents/MacOS/Glance -verify_arch arm64 x86_64
```

Local application bundles receive an ad-hoc signature without hardened runtime when a Developer ID identity is not available. This allows macOS to load bundled frameworks that have no Team ID. Certificate-signed builds keep hardened runtime and timestamping. You do not need the maintainer's signing or notarization credentials to contribute.

`test-panel-window.sh` exercises the actual AppKit menu-bar button and panel, including resize notifications, reopening, and saved-frame restoration. It requires a macOS GUI session but not XCTest; `GLANCE_SDK_PATH` selects a specific installed SDK if needed.

For changes to hover captions, run `zsh scripts/test-tooltip-hover.sh` in a macOS GUI session. It builds for release, opens the actual floating dashboard with fixture rows, and uses Vision to verify rendered tooltips across successive hovers, reopening, and refreshing. `GLANCE_TOOLTIP_CONFIGURATION=debug` selects a debug build. Leave the mouse and keyboard idle during the check; loss of focus or pointer movement is reported separately from a tooltip failure. It restores the previous pointer position and active app afterwards and never uses your GitHub account or Glance profile.

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
