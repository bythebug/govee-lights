#!/bin/sh
# Builds "Govee Lights.app" next to this script. No Xcode project needed.
set -e
cd "$(dirname "$0")"
APP="Govee Lights.app"
mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $arch-apple-macos14.0 GoveeLights.swift -o "/tmp/GoveeLights-$arch"
done
lipo -create /tmp/GoveeLights-arm64 /tmp/GoveeLights-x86_64 -output "$APP/Contents/MacOS/GoveeLights"
rm /tmp/GoveeLights-arm64 /tmp/GoveeLights-x86_64
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>GoveeLights</string>
  <key>CFBundleIdentifier</key><string>com.sverma.goveelights</string>
  <key>CFBundleName</key><string>Govee Lights</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Finds and controls Govee lights on your Wi-Fi.</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "built $(pwd)/$APP"
