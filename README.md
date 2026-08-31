# Glance

Glance is a native macOS pull-request HUD: a menu-bar utility with a detachable, always-on-top panel for the GitHub work that needs your attention.

## Requirements

- macOS 14 or newer
- Xcode 16 or newer
- [GitHub CLI](https://cli.github.com/) authenticated with `gh auth login`

## Build and run

```sh
swift run Glance
```

To create a standalone, ad-hoc-signed application bundle:

```sh
./scripts/build-app.sh
open dist/Glance.app
```

Glance uses saved GitHub search queries for its sections. The built-in sections show pull requests requesting your review and pull requests you opened. Edit or add validated sections in Settings.

Command-click a pull request to remove that revision from Glance. If the pull request receives a new commit, it automatically returns. This shortcut is enabled by default and can be turned off in Settings.

Authentication is read from GitHub CLI at refresh time. Glance does not persist the token. Cached pull-request metadata and preferences live in `~/Library/Application Support/Glance`.

## Connecting GitHub

This preview uses GitHub CLI authentication:

1. Install [GitHub CLI](https://cli.github.com/).
2. Run `gh auth login` and complete GitHub's browser sign-in.
3. Open Glance, or choose **Check Connection** in Settings.

If Glance cannot find an authenticated GitHub CLI account, it shows this setup process in the panel. A generally distributed build should replace this developer-oriented flow with a registered GitHub App and browser-based OAuth/PKCE sign-in.

## Icons

GitHub interface glyphs are from [Primer Octicons](https://github.com/primer/octicons) and are distributed under the MIT License. The license is included with the packaged resources.
