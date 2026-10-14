#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h:h}"
cd "$repo_root"
sdk="$(xcrun --show-sdk-path)"
swift build --build-system native --sdk "$sdk"
binary_path="$(swift build --build-system native --sdk "$sdk" --show-bin-path)"
demo_root="$(mktemp -d /tmp/glance-readme.XXXXXX)"
app_path="$demo_root/Glance Demo.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$demo_root/home"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GlanceDemo</string>
<key>CFBundleIdentifier</key><string>app.glance.readme-demo</string>
<key>CFBundleName</key><string>Glance Demo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp -R "$binary_path/Glance_Glance.bundle" "$app_path/Contents/Resources/"
objects=()
for object in "$binary_path"/Glance.build/*.swift.o; do
  [[ "${object:t}" == "GlanceApp.swift.o" ]] || objects+=("$object")
done
swiftc -sdk "$sdk" -swift-version 5 -parse-as-library \
  -I "$binary_path/Modules" -F "$binary_path" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$binary_path" \
  scripts/readme-media/Demo.swift "${objects[@]}" -o "$app_path/Contents/MacOS/GlanceDemo"
codesign --force --sign - "$app_path"
print "Offline demo: $app_path"
print "Isolated profile: $demo_root/home"
HOME="$demo_root/home" CFFIXED_USER_HOME="$demo_root/home" \
  "$app_path/Contents/MacOS/GlanceDemo" "$demo_root/home"
