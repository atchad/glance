#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
app_path="$repo_root/dist/Glance.app"
dmg_path="$repo_root/dist/Glance.dmg"
background_path="$repo_root/support/dmg-background.png"
temp_root="$(mktemp -d -t glance-dmg)"
staging_path="$temp_root/staging"
read_write_dmg="$temp_root/Glance-rw.dmg"
device=""

cleanup() {
  if [[ -n "$device" ]]; then hdiutil detach "$device" -quiet || true; fi
  rm -rf "$temp_root"
}
trap cleanup EXIT

if [[ ! -f "$background_path" || ! -f "$repo_root/support/Glance.icns" ]]; then
  "$repo_root/scripts/build-assets.sh"
fi
"$repo_root/scripts/build-app.sh" release

if [[ -e "/Volumes/Glance" ]]; then
  print -u2 "A volume named Glance is already mounted. Eject it and try again."
  exit 1
fi

mkdir -p "$staging_path/.background"
cp -R "$app_path" "$staging_path/Glance.app"
ln -s /Applications "$staging_path/Applications"
cp "$background_path" "$staging_path/.background/installer-background.png"

hdiutil create -quiet -ov -format UDRW -fs HFS+ -volname "Glance" \
  -srcfolder "$staging_path" "$read_write_dmg"
device="$(hdiutil attach -readwrite -noverify -noautoopen "$read_write_dmg" \
  | awk '/Apple_HFS/ { print $1; exit }')"

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "Glance"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set sidebar width of container window to 0
    set the bounds of container window to {120, 120, 780, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:installer-background.png"
    set position of item "Glance.app" of container window to {160, 210}
    set position of item "Applications" of container window to {500, 210}
    close
    open
    update without registering applications
  end tell
end tell
delay 2
APPLESCRIPT

sync
hdiutil detach "$device" -quiet
device=""
rm -f "$dmg_path"
hdiutil convert -quiet "$read_write_dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg_path"

signing_identity="${GLANCE_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  signing_identity="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -n 1)"
fi

if [[ -n "$signing_identity" ]]; then
  codesign --force --timestamp --sign "$signing_identity" "$dmg_path"
else
  print -u2 "No Developer ID Application identity found; using an ad-hoc DMG signature."
  codesign --force --sign - "$dmg_path"
fi

if [[ -n "${GLANCE_NOTARY_PROFILE:-}${GLANCE_NOTARY_KEY:-}${GLANCE_NOTARY_KEY_ID:-}${GLANCE_NOTARY_ISSUER_ID:-}" ]]; then
  "$repo_root/scripts/notarize.sh" "$dmg_path"
fi

echo "$dmg_path"
