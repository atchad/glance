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
./scripts/build-app.sh release
codesign --verify --deep --strict --verbose=2 dist/Glance.app
lipo dist/Glance.app/Contents/MacOS/Glance -verify_arch arm64 x86_64
```

Local application bundles receive an ad-hoc signature when a Developer ID identity is not available. You do not need the maintainer's signing or notarization credentials to contribute.

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
