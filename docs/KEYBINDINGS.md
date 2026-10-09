# Keybindings

Glance has one system-wide hotkey and a set of focused commands. There is no leader key.

## Global hotkey

The default is **Control–Shift–Space**:

- If the panel is hidden, show it and give it keyboard focus.
- If the panel is visible but does not have focus, focus it.
- If the panel already has focus, hide it.

Clicking outside the dashboard hides it. Its details popovers and sheets keep the dashboard open. Switching to another app also hides it; returning to Glance does not automatically reopen the panel.

This uses macOS hotkey registration, not a global event tap. It does not need Accessibility permission. If registration fails, Keyboard settings shows an error. Glance cannot detect every shortcut reserved by macOS or another app.

## Focused commands

These commands work in the dashboard panel, opened by either the menu-bar icon or global hotkey. Text fields, native control activation, child popovers, sheets, and open menus keep their normal keys. Command-modified, single-chord app actions also appear in the app menus. Menus show the first such binding for Settings, Check for updates, and Quit.

| Action | Default keys |
| --- | --- |
| Next / previous PR | `j` / `k`, Down / Up |
| First / last PR | `g g` / `shift+g` |
| Focus / clear search | `/` / `shift+/` |
| Open / details | Return / `i` |
| Dismiss / undo dismissal | `d` / `u` or `cmd+z` |
| Pin or unpin | `p` |
| Copy title / URL / branch | `c t` / `c u` / `c b` |
| Snooze one hour / tomorrow / one week | `s h` / `s d` / `s w` |
| Snooze until changes / checks finish | `s c` / `s f` |
| Wake selected snoozed PR | `w` |
| Toggle selected section | `z z` |
| Collapse / expand all sections | `z c` / `z o` |
| Refresh | `r` |
| Show floating panel / hide Glance | `v` / `h` |
| Toggle always on top | `t` |
| Settings | `cmd+,` |
| Quit | `cmd+q` |
| Check for updates | Unbound |

PR commands use the selected, visible row. The Snoozed section defaults to collapsed; click its header to expand or collapse it. Expanded snoozed rows participate in navigation so Wake has a keyboard target. A row's buttons and context menu use that row as an explicit target. Checks-finish snooze is available only while checks are pending. A missing or hidden target cannot run a selected-row action.

After a prefix such as `c`, Glance shows the available next keys. The default timeout is three seconds. Escape cancels. An invalid continuation cancels without running a different action. Focus changes, clicks, selection-list changes, and config reloads also cancel. Holding a key repeats only next/previous navigation, not PR actions.

## PR browser windows

Dashboard bindings do not capture typing inside a GitHub page. PR windows use Command–W
to hide their retained page and Command–R to request a reload, with a warning about losing
unfinished work. The dashboard's `r` refresh only updates Glance's queue metadata; it does
not reload browser pages. Browser window shortcuts are not part of `keybindings.json`.

## Settings and the config file

Open **Settings → Keyboard** to search actions, edit or record bindings, disable them, change the timeout, reveal the file, or reset defaults. Recording temporarily disables the global hotkey so it can be recorded safely.

Both Settings and external editors use:

```text
~/Library/Application Support/Glance/keybindings.json
```

The file stores overrides only:

```json
{
  "version": 1,
  "globalHotkey": "ctrl+shift+space",
  "sequenceTimeout": 3,
  "bindings": {
    "dismiss": ["x"],
    "copyURL": ["c u", "cmd+shift+u"],
    "checkForUpdates": ["ctrl+u"],
    "quit": []
  }
}
```

- An absent action uses its default bindings. An empty array disables its bindings, not its button or menu item.
- Set `globalHotkey` to `null` to turn it off. Omitting it uses the default.
- Use `ctrl`, `alt`, `shift`, and `cmd` joined with `+` for a chord. `alt` means Option.
- Use a space between chords in a sequence. Sequences have one to four chords.
- In the Settings text editor, use `;` between alternative bindings. In JSON, use separate array entries.
- Keys include ASCII characters, `space`, `return`, arrow names, `home`, `end`, `pageup`, `pagedown`, `delete`, `forwarddelete`, and `f1` through `f20`. Escape and Tab are reserved.
- Shift is explicit: use `shift+g`, not uppercase `G`; use `shift+/`, not `?` on a US layout. Key matching uses the current keyboard layout, without modifiers, then applies the listed modifiers.
- The global hotkey is one chord and must include Control, Option, or Command.
- The timeout must be from 0.5 to 30 seconds. The file must be at most 64 KB.

Bindings cannot duplicate another binding or be a prefix of another action. For example, `c` cannot be an action while `c u` exists. Two sequences can share a prefix, such as `c u` and `c t`. Local bindings cannot use the global hotkey as their first chord. Disable or rebind the conflicting action in the same file edit.

External edits reload automatically, including atomic file replacement. Invalid edits leave the last valid in-memory bindings active and show an error. Glance does not rewrite the invalid file. On startup, an invalid file leaves built-in defaults active. Settings re-reads the file before saving; a stale editor cannot overwrite an external edit. Reset preserves an invalid file in a `keybindings.recovery-*.json` copy before replacing it.

The old panel shortcut migrates when Glance first creates this file. A previously selected Option–Space, Control–Space, or Option–G is kept. The old Off/default value adopts Control–Shift–Space. Once the file exists, it is the sole source of truth.

## Implementation and tests

- `Keybindings.swift` defines action IDs, defaults, validation, and the sequence matcher. The matcher takes time and action availability as inputs.
- `KeybindingStore.swift` owns file edits and live reload. It watches the parent folder because editors replace file inodes.
- `KeyboardEvents.swift` adapts native events and menu shortcuts. Its event monitor is scoped to a dashboard window.
- `ApplicationCommands.swift` checks availability and dispatches actions. Views supply current targets; buttons, menus, and keybindings share this path.
- `GlobalShortcutController.swift` owns the one Carbon hotkey registration.

Run `swift test` with full Xcode. For Command Line Tools-only environments, run `zsh scripts/test-keybindings.sh` for matcher, config, watcher, and hotkey-registration checks. Use `GLANCE_SDK_PATH` to choose a compatible SDK for this runner or `scripts/build-app.sh`:

```sh
GLANCE_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk zsh scripts/test-keybindings.sh
GLANCE_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./scripts/build-app.sh
```
