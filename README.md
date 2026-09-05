<p align="center">
  <img src="support/AppIcon.svg" width="128" height="128" alt="Glance app icon">
</p>

<h1 align="center">Glance</h1>

<p align="center">
  A native macOS pull-request HUD for the work that needs your attention.
</p>

Glance keeps your GitHub pull requests one click away in the menu bar. Open its compact popover for a quick check, or detach it into an always-on-top panel while you work.

<p align="center">
  <img src="docs/images/glance-panel.png" width="360" alt="Glance showing pull requests that need attention">
</p>

## What Glance does

- Shows review requests, pull requests you opened, and any other sections you define with GitHub search queries.
- Explains why a pull request needs attention, including review requests, new commits, failed
  checks, unresolved conversations, merge conflicts, and merge readiness.
- Surfaces draft, review, detailed check, merge-queue, auto-merge, and stacked-pull-request status
  without opening a browser.
- Displays an attention count directly in the menu bar.
- Notifies you when a new review request arrives.
- Can notify you when reviews, checks, merge readiness, or merge-queue state changes.
- Lets you pin important pull requests or snooze them until later, until checks finish, or until the pull request changes.
- Supports local search, keyboard triage, and an optional system-wide shortcut for the panel.
- Lets you choose which repositories appear in the app and can generate notifications.
- Keeps the last successful results visible when GitHub is temporarily unavailable.
- Opens at login and refreshes automatically on your preferred schedule.
- Checks for new Glance releases and can install them automatically.

Command-click a pull request to dismiss its current revision. If a new commit is pushed, the pull request returns automatically. Use a row's context menu to pin it or snooze it.

With the panel focused, use the arrow keys or J/K to move between pull requests, Return to open the selected pull request, D to dismiss it, P to pin it, R to refresh, and / to search.

## Install

Glance requires macOS 14 or later and an authenticated installation of [GitHub CLI](https://cli.github.com/).

1. Install GitHub CLI if needed:

   ```sh
   brew install gh
   ```

2. Connect it to GitHub:

   ```sh
   gh auth login
   ```

3. [Download the latest Glance DMG](https://github.com/atchad/glance/releases/latest/download/Glance.dmg), open it, and drag Glance into Applications.
4. Launch Glance. Its pull-request count will appear in the menu bar.

Glance releases are universal for Apple silicon and Intel Macs, signed with a Developer ID certificate, and notarized by Apple.

## Make it yours

Glance labels a review request as yours when GitHub names your account directly or confirms your membership in the requested team (including child teams). Unavailable membership or incomplete request data is treated as unknown. Review-request dates come only from matching personal or team events; an unavailable date falls back to the PR creation date in the row.

Glance starts with sections for pull requests requesting your review and pull requests you opened. In Settings, you can:

- Add, rename, reorder, or remove sections backed by validated GitHub pull-request searches.
- Include or exclude repositories with search and bulk selection.
- Choose which pull requests contribute to the menu-bar count, including whether review requests
  also count pull requests you opened.
- Sort each section by attention, review-request time, recent activity, repository, or stack order.
- Control notifications, refresh frequency, launch behavior, and panel behavior.
- Choose which pull-request transitions generate notifications and configure a global panel shortcut.
- Adjust row details, including optional additions and deletions, status presentation, and
  completed-review filtering.

Click a pull request to open it on GitHub. Its context menu can also copy the URL or branch name.

## Privacy and local data

Glance asks GitHub CLI for your existing token when it refreshes and does not persist that token itself. Pull-request metadata and preferences are stored locally in:

```text
~/Library/Application Support/Glance
```

Excluding a repository removes its pull requests from the live queue and local cache and prevents new-review notifications from that repository.

## Build from source

Building Glance requires macOS 14 or later and Xcode 16 or later.

```sh
git clone https://github.com/atchad/glance.git
cd glance
./scripts/build-app.sh
open dist/Glance.app
```

Run the test suite with:

```sh
swift test
```

Create a standalone application bundle or DMG with:

```sh
./scripts/build-app.sh
./scripts/build-dmg.sh
```

Without a Developer ID certificate in your Keychain, local artifacts receive an ad-hoc signature. Maintainer signing, notarization, and tagged-release instructions are documented in [docs/RELEASING.md](docs/RELEASING.md).

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for development checks and pull-request guidance. Report suspected vulnerabilities through the private channel described in [SECURITY.md](SECURITY.md).

## Acknowledgments

GitHub interface glyphs are from [Primer Octicons](https://github.com/primer/octicons) and are distributed under the MIT License. The packaged license is included in [`Sources/Glance/Resources/Octicons/LICENSE`](Sources/Glance/Resources/Octicons/LICENSE).

Glance itself is available under the [MIT License](LICENSE).

Automatic updates use [Sparkle](https://sparkle-project.org/), distributed under its included license at `Glance.app/Contents/Resources/Sparkle-LICENSE.txt`.
