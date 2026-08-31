#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
app_path="$repo_root/dist/Glance.app"
pkg_path="$repo_root/dist/Glance.pkg"
temp_root="$(mktemp -d -t glance-pkg)"
payload_root="$temp_root/payload"
component_plist="$temp_root/components.plist"

cleanup() {
  rm -rf "$temp_root"
}
trap cleanup EXIT

"$repo_root/scripts/build-app.sh" release

app_version="$(plutil -extract CFBundleShortVersionString raw \
  "$app_path/Contents/Info.plist")"
installer_identity="${GLANCE_INSTALLER_IDENTITY:-}"

if [[ -z "$installer_identity" ]]; then
  installer_identity="$(security find-identity -v -p basic \
    | sed -n 's/.*"\(Developer ID Installer:[^"]*\)".*/\1/p' \
    | head -n 1)"
fi

if [[ -z "$installer_identity" ]]; then
  print -u2 "No Developer ID Installer identity found. Refusing to build an unsigned distribution package."
  exit 1
fi

rm -f "$pkg_path"
mkdir -p "$payload_root/Applications"
COPYFILE_DISABLE=1 cp -R "$app_path" "$payload_root/Applications/Glance.app"
xattr -cr "$payload_root/Applications/Glance.app"
codesign --verify --deep --strict "$payload_root/Applications/Glance.app"

pkgbuild --analyze --root "$payload_root" "$component_plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$component_plist"
plutil -replace 0.BundleIsVersionChecked -bool YES "$component_plist"
plutil -replace 0.BundleHasStrictIdentifier -bool YES "$component_plist"

pkgbuild \
  --root "$payload_root" \
  --component-plist "$component_plist" \
  --install-location / \
  --identifier com.anthonychadwick.glance.pkg \
  --version "$app_version" \
  --sign "$installer_identity" \
  --timestamp \
  "$pkg_path"

pkgutil --check-signature "$pkg_path"

if [[ -n "${GLANCE_NOTARY_PROFILE:-}${GLANCE_NOTARY_KEY:-}${GLANCE_NOTARY_KEY_ID:-}${GLANCE_NOTARY_ISSUER_ID:-}" ]]; then
  "$repo_root/scripts/notarize.sh" "$pkg_path"
fi

echo "$pkg_path"
