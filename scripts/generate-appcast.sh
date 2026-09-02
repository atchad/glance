#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
app_path="$repo_root/dist/Glance.app"
dmg_path="$repo_root/dist/Glance.dmg"
appcast_path="$repo_root/dist/appcast.xml"
sparkle_root="$repo_root/.build/artifacts/sparkle/Sparkle"
generate_appcast="$sparkle_root/bin/generate_appcast"
archive_root="$(mktemp -d -t glance-appcast)"

cleanup() {
  rm -rf "$archive_root"
}
trap cleanup EXIT

[[ -d "$app_path" ]] || { print -u2 "Build Glance.app before generating the appcast."; exit 1; }
[[ -f "$dmg_path" ]] || { print -u2 "Build Glance.dmg before generating the appcast."; exit 1; }
[[ -x "$generate_appcast" ]] || {
  print -u2 "Sparkle's generate_appcast tool is unavailable. Run swift package resolve."
  exit 1
}

version="$(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist")"
build="$(plutil -extract CFBundleVersion raw "$app_path/Contents/Info.plist")"
tag="v$version"
download_url="https://github.com/atchad/glance/releases/download/$tag/Glance.dmg"
cp "$dmg_path" "$archive_root/Glance.dmg"

previous_tag="$(
  git -C "$repo_root" tag --merged HEAD --sort=-version:refname \
    | awk -v current="$tag" '$0 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ && $0 != current { print; exit }'
)"
if [[ -n "$previous_tag" ]]; then
  git -C "$repo_root" log --format='- %s' "$previous_tag..HEAD" > "$archive_root/Glance.md"
else
  git -C "$repo_root" log -1 --format='- %s' HEAD > "$archive_root/Glance.md"
fi

arguments=(
  --download-url-prefix "https://github.com/atchad/glance/releases/download/$tag/"
  --embed-release-notes
  --full-release-notes-url "https://github.com/atchad/glance/releases"
  --link "https://github.com/atchad/glance"
  --maximum-deltas 0
  -o "$appcast_path"
)

if [[ -n "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" \
    | "$generate_appcast" --ed-key-file - "${arguments[@]}" "$archive_root"
else
  "$generate_appcast" --account app.glance.Glance "${arguments[@]}" "$archive_root"
fi

xmllint --noout "$appcast_path"
grep -q 'sparkle:edSignature=' "$appcast_path"
grep -q 'sparkle-signatures:' "$appcast_path"
[[ "$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@url)' "$appcast_path")" == "$download_url" ]]
[[ "$(xmllint --xpath 'string(//*[local-name()="version"])' "$appcast_path")" == "$build" ]]
[[ "$(xmllint --xpath 'string(//*[local-name()="shortVersionString"])' "$appcast_path")" == "$version" ]]
print "$appcast_path"
