#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
sdk="${GLANCE_SDK_PATH:-$(xcrun --show-sdk-path)}"
cd "$repo_root"
swift build --build-system native --sdk "$sdk"
binary_path="$(swift build --build-system native --sdk "$sdk" --show-bin-path)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/glance-color-window.XXXXXX")"
app_path="$test_directory/RepositoryColorChecks.app"
mkdir -p "$app_path/Contents/MacOS"
trap 'rm -f "$app_path/Contents/MacOS/RepositoryColorChecks" "$app_path/Contents/Info.plist" "$test_directory/keybindings.json" "$test_directory/preferences.json" "$test_directory/cache.json"; rmdir "$app_path/Contents/MacOS" "$app_path/Contents" "$app_path" "$test_directory"' EXIT
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RepositoryColorChecks</string>
<key>CFBundleIdentifier</key><string>app.glance.repository-color-checks</string>
<key>CFBundleName</key><string>Glance Repository Color Checks</string>
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
  "$repo_root/scripts/test-repository-color-window.swift" "${objects[@]}" \
  -o "$app_path/Contents/MacOS/RepositoryColorChecks"
"$app_path/Contents/MacOS/RepositoryColorChecks" "$test_directory"
