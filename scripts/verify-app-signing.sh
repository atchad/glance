#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
app_path="${1:-$repo_root/dist/Glance.app}"
codesign --verify --deep --strict "$app_path"
signing_details="$(codesign --display --verbose=4 "$app_path" 2>&1)"

if [[ "$signing_details" == *"Signature=adhoc"* ]]; then
    if print -r -- "$signing_details" | grep -Eq 'flags=.*runtime'; then
        print -u2 "Ad-hoc builds must not enable hardened runtime. macOS can reject bundled frameworks without a Team ID."
        exit 1
    fi
elif ! print -r -- "$signing_details" | grep -Eq 'flags=.*runtime'; then
    print -u2 "Certificate-signed builds must enable hardened runtime."
    exit 1
fi
