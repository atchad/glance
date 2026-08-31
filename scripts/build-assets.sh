#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
icon_source="$repo_root/support/AppIcon.svg"
iconset_path="$repo_root/support/AppIcon.iconset"
icon_path="$repo_root/support/Glance.icns"
background_source="$repo_root/support/dmg-background.svg"
background_path="$repo_root/support/dmg-background.png"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  print -u2 "rsvg-convert is required to rebuild installer artwork (brew install librsvg)."
  exit 1
fi

rm -rf "$iconset_path"
mkdir -p "$iconset_path"

for size in 16 32 128 256 512; do
  rsvg-convert --width "$size" --height "$size" "$icon_source" \
    --output "$iconset_path/icon_${size}x${size}.png"
  retina_size=$((size * 2))
  rsvg-convert --width "$retina_size" --height "$retina_size" "$icon_source" \
    --output "$iconset_path/icon_${size}x${size}@2x.png"
done

iconutil --convert icns --output "$icon_path" "$iconset_path"
rm -rf "$iconset_path"
rsvg-convert --width 660 --height 400 "$background_source" --output "$background_path"

echo "$icon_path"
echo "$background_path"
