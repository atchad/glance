#!/bin/zsh
set -euo pipefail

configuration="${1:-release}"
repo_root="${0:A:h:h}"
cd "$repo_root"

swift build -c "$configuration"
binary_path="$(swift build -c "$configuration" --show-bin-path)/Glance"
binary_directory="${binary_path:h}"
app_path="$repo_root/dist/Glance.app"
contents_path="$app_path/Contents"

rm -rf "$app_path"
mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$binary_path" "$contents_path/MacOS/Glance"
cp -R "$binary_directory/Glance_Glance.bundle" "$contents_path/Resources/Glance_Glance.bundle"
cp "$repo_root/support/Info.plist" "$contents_path/Info.plist"
codesign --force --deep --sign - "$app_path"

echo "$app_path"
