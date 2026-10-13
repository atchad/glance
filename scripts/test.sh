#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"
export GLANCE_SDK_PATH="${GLANCE_SDK_PATH:-$(xcrun --show-sdk-path)}"
build_arguments=(--build-system native --sdk "$GLANCE_SDK_PATH")
if [[ -n "${GLANCE_BUILD_PATH:-}" ]]; then
  build_arguments+=(--scratch-path "$GLANCE_BUILD_PATH")
fi
case "${1:-}" in
  ""|--unit-only) ;;
  *) print -u2 "Usage: $0 [--unit-only]"; exit 1 ;;
esac

# Use exactly the same SDK and backend as the bundled integration runners.
swift test "${build_arguments[@]}"
python3 scripts/test-release-notes.py
python3 scripts/test-build-installers.py
if [[ "${1:-}" == --unit-only ]]; then exit 0; fi

export GLANCE_TEST_BIN_PATH="$(swift build "${build_arguments[@]}" --show-bin-path)"
zsh scripts/test-keybindings.sh
zsh scripts/test-panel-window.sh
zsh scripts/test-repository-color-window.sh
zsh scripts/test-pr-browser.sh
