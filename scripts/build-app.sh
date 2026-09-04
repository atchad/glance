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
frameworks_path="$contents_path/Frameworks"
sparkle_framework_source="$binary_directory/Sparkle.framework"
sparkle_framework="$frameworks_path/Sparkle.framework"
sparkle_license="$repo_root/.build/artifacts/sparkle/Sparkle/LICENSE"

rm -rf "$app_path"
mkdir -p "$contents_path/MacOS" "$contents_path/Resources" "$frameworks_path"
cp "$binary_path" "$contents_path/MacOS/Glance"
cp -R "$binary_directory/Glance_Glance.bundle" "$contents_path/Resources/Glance_Glance.bundle"
cp "$repo_root/support/Info.plist" "$contents_path/Info.plist"
if [[ -n "${GLANCE_GITHUB_OAUTH_CLIENT_ID:-}" ]]; then
    /usr/bin/plutil -insert GlanceGitHubOAuthClientID -string \
        "$GLANCE_GITHUB_OAUTH_CLIENT_ID" "$contents_path/Info.plist" 2>/dev/null \
        || /usr/bin/plutil -replace GlanceGitHubOAuthClientID -string \
            "$GLANCE_GITHUB_OAUTH_CLIENT_ID" "$contents_path/Info.plist"
fi
cp "$repo_root/support/Glance.icns" "$contents_path/Resources/Glance.icns"
cp "$sparkle_license" "$contents_path/Resources/Sparkle-LICENSE.txt"
ditto "$sparkle_framework_source" "$sparkle_framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$contents_path/MacOS/Glance"

signing_identity="${GLANCE_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
        | head -n 1)"
fi

if [[ -z "$signing_identity" ]]; then
    print -u2 "No Developer ID Application identity found; using an ad-hoc signature."
    signing_identity="-"
fi

signing_arguments=(--force --options runtime --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then
    signing_arguments+=(--timestamp)
fi

codesign "${signing_arguments[@]}" \
    "$sparkle_framework/Versions/B/XPCServices/Installer.xpc"
codesign "${signing_arguments[@]}" --preserve-metadata=entitlements \
    "$sparkle_framework/Versions/B/XPCServices/Downloader.xpc"
codesign "${signing_arguments[@]}" "$sparkle_framework/Versions/B/Autoupdate"
codesign "${signing_arguments[@]}" "$sparkle_framework/Versions/B/Updater.app"
codesign "${signing_arguments[@]}" "$sparkle_framework"
codesign "${signing_arguments[@]}" "$app_path"

echo "$app_path"
