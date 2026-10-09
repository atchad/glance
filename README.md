<p align="center">
  <img src="support/AppIcon.svg" width="128" height="128" alt="Glance app icon">
</p>

<h1 align="center">Glance</h1>

<p align="center">
  A native macOS pull-request HUD for the work that needs your attention.
</p>

Glance keeps your GitHub pull requests one click away in the menu bar. Click its icon or use the global hotkey to open the same resizable, always-on-top panel while you work.
Click outside the panel to hide it; its details popovers remain part of the panel.

<p align="center">
  <img src="docs/images/glance-panel.png" width="360" alt="Glance showing pull requests that need attention">
</p>

## What Glance does

- Shows review requests, pull requests you opened, and any other sections you define with GitHub search queries.
- Explains why a pull request needs attention, including repeated review requests, new commits,
  failed checks, unresolved conversations, merge conflicts, and merge readiness.
- Surfaces draft, review, aggregate check, merge-queue, auto-merge, and stacked-pull-request status
  without opening a browser.
- Displays an attention count directly in the menu bar.
- Notifies you when a new review request arrives.
- Can notify you when reviews, checks, merge readiness, or merge-queue state changes.
- Lets you pin important pull requests or snooze them until later, until checks finish, or until the pull request changes.
- Read the full title and fetched check details using a row’s info button or I on the selected row. Copy title preserves the exact title. Check details identify cached data and may omit checks that exist on GitHub.
- Supports local search, keyboard triage, and an optional system-wide shortcut for the panel. J/K or arrows traverse expanded search results; Return opens, D dismisses, and P toggles a pin on the selected row. Duplicate PRs are visited in section order. Hiding a selected row clears selection. Slash focuses search, where normal text editing takes precedence.
- Lets you choose which repositories appear in the app and can generate notifications.
- Keeps the last successful results visible when GitHub is temporarily unavailable.
- Preloads listed PRs in native browser windows. Closing a window hides its live page;
  reopening retains scroll position, unfinished comments, and expanded discussions.
- Opens at login and refreshes automatically on your preferred schedule.
- Checks for new Glance releases and can install them automatically.

Command-click a pull request to dismiss its current revision. If a new commit is pushed, the pull request returns automatically. Use a row's context menu to pin it or snooze it.

Press Control–Shift–Space to show and focus Glance from any app. Press it again while the panel has focus to hide it. With the dashboard focused, use the arrow keys or J/K to move between pull requests, Return to open the selected pull request, D to dismiss it, P to pin it, R to refresh, and / to search. Short sequences add more actions: C then U copies a URL; S then H snoozes for one hour. Prefixes show available next keys; Escape cancels.

Settings → Keyboard lets you edit or record bindings. The same bindings live in `~/Library/Application Support/Glance/keybindings.json`, which reloads after external edits. See `docs/KEYBINDINGS.md` for all actions, defaults, config syntax, and focus rules.

## Install

Glance requires macOS 14 or later and an authenticated installation of [GitHub CLI](https://cli.github.com/).

1. Install GitHub CLI if needed:

   ```sh
   brew install gh
   ```

2. Connect it to GitHub:

   ```sh
   gh auth login --hostname github.com
   ```

3. [Download the latest Glance DMG](https://github.com/atchad/glance/releases/latest/download/Glance.dmg), open it, and drag Glance into Applications.
4. Launch Glance. Its pull-request count will appear in the menu bar.

Glance currently connects to github.com using the account selected by GitHub CLI for that host. If the wrong account appears, use `gh auth status --hostname github.com` and `gh auth switch --hostname github.com --user YOUR_USERNAME`, then refresh Glance. If authentication has expired, run `gh auth login --hostname github.com` again. Do not paste tokens into Glance or troubleshooting reports.

Glance releases are universal for Apple silicon and Intel Macs, signed with a Developer ID certificate, and notarized by Apple.

## Make it yours

Glance labels a review request as yours when GitHub names your account directly or confirms your membership in the requested team (including child teams). Unavailable membership or incomplete request data is treated as unknown. Review-request dates come only from matching personal or team events; an unavailable date falls back to the PR creation date in the row.

Dismissed reviews do not count as your approval, so they remain visible under the default approval filter when returned by a section’s query. Their review date and commit still support personal re-request and new-commit attention. The optional filter for approvals from other reviewers still applies independently. Older cached approvals remain unchanged until fresh GitHub data replaces them; previously hidden PRs require a successful refresh to return.

Glance starts with sections for pull requests requesting your review and pull requests you opened. In Settings, you can:

- Add, rename, reorder, or remove sections backed by validated GitHub pull-request searches. The Add section Examples menu fills editable drafts for assigned PRs, your non-draft PRs, or a repository. Replace the repository template, validate, then add; visibility preferences still apply.
- Include or exclude repositories with search and bulk selection.
- Customize repository name colors in Settings → Repo Colors. New repositories cycle through ten
  distinct presets, and assignments persist across launches and future pull requests. Choose a preset
  or use the native color picker’s wheel for a custom color. Right-click a repository name and choose
  Change Repo Color… to jump directly to its settings. Presets adapt to light and dark appearance;
  custom colors stay exact.
- Choose which pull requests contribute to the menu-bar count, including whether review requests
  also count pull requests you opened.
- Sort each section by attention, review-request time, recent activity, repository, or stack order.
- Control notifications, refresh frequency, launch behavior, and panel behavior.
- Drag the panel’s edges or corners to resize it. The menu-bar icon and global hotkey open the same native window, and Glance remembers its size and position across launches.
- Choose which pull-request transitions generate notifications and configure a global panel shortcut.
- Adjust row details, including optional additions and deletions, review and check status icons,
  and completed-review filtering. Each row shows the time elapsed since the PR was created or
  your review was requested, such as 5m, 3h, or 2d.
- Rows stay two lines: metadata above a single-line title. Attention reasons appear as icons
  between the status icons and repository name; hover over an icon for its caption. Open Details
  to read or copy a full title when it is truncated.

Click a pull request to open it in the application selected in Settings → General → Links.
Its context menu can also copy the URL or branch name.

### Choose where links open

The **Open links with** dropdown offers Default browser, Glance, applications recommended
by macOS for HTTPS links, and Choose application… to pick an application from disk. A custom
selection remains in the dropdown and persists across launches. This setting applies to
PRs, fetched check links, and notification links; it does not change your Mac's default
browser. If the selected application moves, Glance tries to find it by bundle identifier.
If it is removed or cannot open the link, Glance falls back to your default browser and
shows a warning. Glance remains the default for existing and new profiles.

Selecting Glance shows a **GitHub website** row below the dropdown. **Log in…** opens GitHub's
normal login page in a dedicated window sharing the PR windows' WebKit cookie store. The
row switches to **Log out…** when it detects an unexpired GitHub login/session cookie pair,
and shows the account name when GitHub supplies it. This is a local website-session indicator,
not server verification: a stored session may expire or be revoked. Sign in using the same
account as GitHub CLI; Glance does not exchange CLI or OAuth/API tokens for website cookies.

Logging out asks for confirmation, closes all Glance browser windows (including hidden
pages), discards unfinished work, and clears GitHub website cookies and storage in Glance.
It does not sign out GitHub CLI, other browsers, or unrelated websites. The dropdown hides
this authentication row when another application is selected.

Selecting another application stops new background preloads and releases never-opened
preloads. Pages you have opened remain intact until their PR leaves the dashboard or you
quit; switching back to Glance reuses them.

### Persistent PR windows

When Glance is selected as the link-opening application, it gradually preloads one GitHub
page per unique listed PR, including rows in collapsed
sections and rows hidden by local search. There is no page-count limit; large queues can use
substantial memory. Clicking a PR before its preload finishes shows the page while it loads.
Repeated clicks bring the same window forward. The close button and Command–W hide the window
without navigating or reloading it, preserving its current GitHub tab, scroll position,
expanded sections, and unfinished work during this Glance session.

Sign in using Settings → General → Links → Log in… or inside a PR window once. These windows share a persistent WebKit cookie
store, separate from Safari, Chrome, and GitHub CLI authentication. Never-opened preloads
are reloaded when the browser sign-in changes; pages you have opened are not. Use the window's
Back, Forward, Reload, and Open in Default Browser controls as needed. External links and
new-window links open in your default browser. Some organization sign-in or popup-based
authentication flows may require using your regular browser instead.

Glance's queue refresh updates PR metadata but does **not** reload these browser pages.
GitHub controls its own live page updates; hidden pages can be throttled and live connections
can stall. Glance does not periodically reload pages or promise that they are always current.
Reload (Command–R) asks for confirmation because it can lose a comment draft, review edits,
expanded sections, or scroll position. A WebKit process failure shows a recovery message
instead of silently reloading.

When a PR leaves all configured sections or is hidden by dismissal, approval filters,
or repository exclusion, Glance automatically closes and discards its page, **including
unfinished work**, even if the window is visible. This also cleans up merged or closed PRs
when they leave a section's search results. A failed refresh retains the existing results
and their pages. Removing a PR from one section does not discard it if it remains in another.
Snoozed PRs remain listed in the dashboard's Snoozed section and retain their pages.
Quitting Glance discards all live pages; sign-in persists, but live page state is not restored
after relaunch or a WebKit process crash.

## Privacy and local data

Glance asks GitHub CLI for your existing token when it refreshes and does not persist that token itself. Pull-request metadata and preferences are stored locally in:

```text
~/Library/Application Support/Glance
```

Preloading contacts GitHub for each listed PR even before you open its window. Embedded GitHub
pages use normal WebKit website storage (cookies, cache, and website-managed data), which may
contain private content. Glance does not inject the CLI token into pages or collect comment
drafts. Discarding a page releases its live view; it does not erase shared website storage.

Excluding a repository removes its pull requests from the live queue and local cache and prevents new notifications from that repository. This filters the active app data; it does not erase recovery copies, external backups, previously delivered notifications, or matching text in saved queries and preferences.

Missing local files are normal on first launch. If existing files are damaged or contain invalid values, Glance preserves a recovery copy beside them when possible and shows a warning. If it cannot preserve the original, it disables writes to that file. Save failures are also shown; do not assume recent changes survived quitting while a save-error warning remains. Recovery copies can contain private PR metadata.

Approved PRs hidden by your filters are omitted from the offline cache unless pinned. After a restart, making those filters less restrictive may require a successful refresh to bring the PRs back. A pin does not override a repository exclusion.

Check icons summarize GitHub's aggregate rollup. Glance does not offer a complete check-detail viewer; open the PR on GitHub for individual logs and the full list. When fetched detail is incomplete, attention captions avoid an exact failing-check count.

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
./scripts/build-dmg.sh --use-existing-app
./scripts/build-pkg.sh --use-existing-app
```

Without a Developer ID certificate in your Keychain, local artifacts receive an ad-hoc signature. Maintainer signing, notarization, and tagged-release instructions are documented in [docs/RELEASING.md](docs/RELEASING.md).

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for development checks and pull-request guidance. Report suspected vulnerabilities through the private channel described in [SECURITY.md](SECURITY.md).

## Acknowledgments

GitHub interface glyphs are from [Primer Octicons](https://github.com/primer/octicons) and are distributed under the MIT License. The packaged license is included in [`Sources/Glance/Resources/Octicons/LICENSE`](Sources/Glance/Resources/Octicons/LICENSE).

Glance itself is available under the [MIT License](LICENSE).

Automatic updates use [Sparkle](https://sparkle-project.org/), distributed under its included license at `Glance.app/Contents/Resources/Sparkle-LICENSE.txt`.
