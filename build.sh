#!/bin/sh
# Builds "LightOS.app" next to this script. No Xcode project needed.
set -e
cd "$(dirname "$0")"
APP="LightOS.app"
mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $arch-apple-macos14.0 LightOS.swift -o "/tmp/LightOS-$arch"
done
lipo -create /tmp/LightOS-arm64 /tmp/LightOS-x86_64 -output "$APP/Contents/MacOS/LightOS"
rm /tmp/LightOS-arm64 /tmp/LightOS-x86_64

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET" "$APP/Contents/Resources"
swift icon.swift "$ICONSET/icon_512x512@2x.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -r "$(dirname "$ICONSET")"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>LightOS</string>
  <key>CFBundleIdentifier</key><string>com.bythebug.lightos</string>
  <key>CFBundleName</key><string>LightOS</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 bythebug · github.com/bythebug</string>
  <key>LSUIElement</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Finds and controls Govee lights on your Wi-Fi.</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "built $(pwd)/$APP"
