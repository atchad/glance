#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
sdk="${GLANCE_SDK_PATH:-$(xcrun --show-sdk-path)}"
configuration="${GLANCE_TOOLTIP_CONFIGURATION:-release}"
cd "$repo_root"
swift build --build-system native -c "$configuration" --sdk "$sdk" -Xswiftc -enable-testing
binary_path="$(swift build --build-system native -c "$configuration" --sdk "$sdk" --show-bin-path)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/glance-tooltip-hover.XXXXXX")"
app_path="$test_directory/TooltipHoverChecks.app"
mkdir -p "$app_path/Contents/MacOS"
trap 'rm -f "$app_path/Contents/MacOS/TooltipHoverChecks" "$app_path/Contents/Info.plist" "$test_directory/keybindings.json" "$test_directory/preferences.json" "$test_directory/cache.json"; rmdir "$app_path/Contents/MacOS" "$app_path/Contents" "$app_path" "$test_directory"' EXIT
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TooltipHoverChecks</string>
<key>CFBundleIdentifier</key><string>app.glance.tooltip-hover-checks</string>
<key>CFBundleName</key><string>Glance Tooltip Hover Checks</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
objects=()
for object in "$binary_path"/Glance.build/*.swift.o; do
  [[ "${object:t}" == "GlanceApp.swift.o" ]] || objects+=("$object")
done
swiftc -sdk "$sdk" -swift-version 5 -parse-as-library \
  -I "$binary_path/Modules" -F "$binary_path" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$binary_path" \
  "$repo_root/scripts/test-tooltip-hover.swift" "${objects[@]}" \
  -o "$app_path/Contents/MacOS/TooltipHoverChecks"
"$app_path/Contents/MacOS/TooltipHoverChecks" "$test_directory"
