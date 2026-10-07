#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
sdk="${GLANCE_SDK_PATH:-$(xcrun --show-sdk-path)}"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/glance-keybindings.XXXXXX")"
trap 'rm -f "$test_directory/tests"; rmdir "$test_directory"' EXIT
swiftc -sdk "$sdk" -swift-version 5 -parse-as-library \
  "$repo_root/Sources/Glance/Keybindings.swift" \
  "$repo_root/Sources/Glance/KeybindingStore.swift" \
  "$repo_root/Sources/Glance/KeyboardEvents.swift" \
  "$repo_root/Sources/Glance/DetailActionButton.swift" \
  "$repo_root/Sources/Glance/GlobalShortcutController.swift" \
  "$repo_root/scripts/test-keybindings.swift" -o "$test_directory/tests"
"$test_directory/tests"
