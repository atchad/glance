#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
sdk="${GLANCE_SDK_PATH:-$(xcrun --show-sdk-path)}"
cd "$repo_root"
# The native backend exposes individual object files and supports this runner without XCTest.
# The suite supplies its already-built native debug products. Standalone runs build first.
if [[ -n "${GLANCE_TEST_BIN_PATH:-}" ]]; then
    binary_path="$GLANCE_TEST_BIN_PATH"
else
    build_arguments=(--build-system native --sdk "$sdk")
    if [[ -n "${GLANCE_BUILD_PATH:-}" ]]; then
        build_arguments+=(--scratch-path "$GLANCE_BUILD_PATH")
    fi
    swift build "${build_arguments[@]}"
    binary_path="$(swift build "${build_arguments[@]}" --show-bin-path)"
fi
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/glance-panel-window.XXXXXX")"
app_path="$test_directory/PanelWindowChecks.app"
mkdir -p "$app_path/Contents/MacOS"
trap 'rm -f "$app_path/Contents/MacOS/PanelWindowChecks" "$app_path/Contents/Info.plist"; rmdir "$app_path/Contents/MacOS" "$app_path/Contents" "$app_path" "$test_directory"' EXIT
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PanelWindowChecks</string>
<key>CFBundleIdentifier</key><string>app.glance.panel-window-checks</string>
<key>CFBundleName</key><string>Glance Panel Window Checks</string>
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
    "$repo_root/Tests/GlanceTests/PanelWindowChecks.swift" \
    "$repo_root/scripts/test-panel-window.swift" "${objects[@]}" \
    -o "$app_path/Contents/MacOS/PanelWindowChecks"
"$app_path/Contents/MacOS/PanelWindowChecks"
