#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! xcrun --find swift >/dev/null 2>&1; then
  echo 'Install Xcode Command Line Tools first: xcode-select --install'
  read -r -p 'Press Return to exit.'
  exit 1
fi
swift build -c debug
BIN_DIR="$(swift build -c debug --show-bin-path)"
APP="$PWD/dist/Alexia HUB Personal.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/AlexiaHubPersonal" "$APP/Contents/MacOS/AlexiaHubPersonal"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AlexiaHubPersonal</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>com.alexiahub.personal</string>
<key>CFBundleName</key><string>Alexia HUB Personal</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.2</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$APP/Contents/Resources"
cp "Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
open "$APP"
echo "Built: $APP"
