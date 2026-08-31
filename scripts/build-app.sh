#!/bin/zsh
set -euo pipefail

configuration="${1:-release}"
repo_root="${0:A:h:h}"
cd "$repo_root"

if [[ ! -f "$repo_root/support/Glance.icns" ]]; then
    "$repo_root/scripts/build-assets.sh" >/dev/null
fi

build_arguments=(-c "$configuration")
if [[ "$configuration" == "release" && "${GLANCE_UNIVERSAL_BUILD:-1}" != "0" ]]; then
    build_arguments+=(--arch arm64 --arch x86_64)
fi

swift build "${build_arguments[@]}"
binary_path="$(swift build "${build_arguments[@]}" --show-bin-path)/Glance"
binary_directory="${binary_path:h}"
app_path="$repo_root/dist/Glance.app"
contents_path="$app_path/Contents"

rm -rf "$app_path"
mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$binary_path" "$contents_path/MacOS/Glance"
cp -R "$binary_directory/Glance_Glance.bundle" "$contents_path/Resources/Glance_Glance.bundle"
cp "$repo_root/support/Info.plist" "$contents_path/Info.plist"
cp "$repo_root/support/Glance.icns" "$contents_path/Resources/Glance.icns"

signing_identity="${GLANCE_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
        | head -n 1)"
fi

if [[ -n "$signing_identity" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_path"
else
    print -u2 "No Developer ID Application identity found; using an ad-hoc signature."
    codesign --force --deep --sign - "$app_path"
fi

echo "$app_path"
