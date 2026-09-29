#!/bin/sh
# Builds NotchVoice.app (release, ad-hoc signed). No Xcode needed — Command Line Tools are enough.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/NotchVoice.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/NotchVoice "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.puneet.NotchVoice</string>
  <key>CFBundleName</key><string>NotchVoice</string>
  <key>CFBundleExecutable</key><string>NotchVoice</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Alternate</string><key>LSItemContentTypes</key><array><string>public.item</string></array></dict></array>
  <key>NSMicrophoneUsageDescription</key><string>NotchVoice listens for “Hey Notch” and your commands. Audio never leaves this Mac.</string>
  <key>NSAppleEventsUsageDescription</key><string>NotchVoice reads the file you have selected in Finder when you ask it to.</string>
</dict></plist>
EOF
# Stable local identity (scripts/setup.sh creates it) so macOS keeps mic + Accessibility grants across rebuilds.
ID=$(security find-identity -p codesigning | awk '/NotchVoice Local Signing/ {print $2; exit}')
codesign -f -s "${ID:--}" "$APP"
echo "built $APP"
