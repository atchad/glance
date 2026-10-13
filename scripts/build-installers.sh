#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"
# Both packagers copy the same verified app and use independent temporary directories.
zsh scripts/build-app.sh release
log_directory="$(mktemp -d -t glance-installers)"
trap 'rm -rf "$log_directory"' EXIT

# Each packager also submits and staples its own artifact. Overlap Apple's waits.
zsh scripts/build-dmg.sh --use-existing-app > "$log_directory/dmg.log" 2>&1 &
dmg_pid=$!
zsh scripts/build-pkg.sh --use-existing-app > "$log_directory/pkg.log" 2>&1 &
pkg_pid=$!

# Always wait for BOTH processes, including when one fails, before keychain cleanup
# or any later release step. Keep each complete log readable and retain failures.
result=0
if ! wait "$dmg_pid"; then result=1; fi
if ! wait "$pkg_pid"; then result=1; fi
print -r -- '--- DMG packaging and notarization ---'
cat "$log_directory/dmg.log"
print -r -- '--- PKG packaging and notarization ---'
cat "$log_directory/pkg.log"
exit "$result"
