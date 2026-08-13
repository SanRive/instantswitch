#!/bin/sh
# Builds InstantSwitch.app — the standalone menu bar version.
#
# No Hammerspoon needed: the app owns the mouse-button event tap itself.
# Plain C/Objective-C, so Command Line Tools is enough (no Xcode, no Swift).
set -e
cd "$(dirname "$0")"

APP="${1:-./InstantSwitch.app}"
MACOS="$APP/Contents/MacOS"
BUNDLE_ID="com.instantswitch.app"

rm -rf "$APP"
mkdir -p "$MACOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>InstantSwitch</string>
    <key>CFBundleDisplayName</key>       <string>InstantSwitch</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>        <string>InstantSwitch</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <!-- Menu bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key>               <true/>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
</dict>
</plist>
PLIST

clang -O2 -fobjc-arc -o "$MACOS/InstantSwitch" \
    src/app_main.m src/ISS.c src/event_serialize.c src/predictions.c \
    -Isrc -Isrc/include \
    -framework Cocoa -framework ApplicationServices -framework CoreGraphics -framework ServiceManagement

# Ad-hoc sign so the bundle has a stable identity for the permission grant.
# NOTE: the grant is tied to the code hash. Rebuilding invalidates it and the
# app must be removed and re-added in System Settings.
codesign --force --deep --sign - "$APP"

echo "built: $APP"
echo
echo "Next:"
echo "  1. open $APP"
echo "  2. System Settings > Privacy & Security > Device Control and Data Access"
echo "     > + > select $APP  (on macOS 26 and earlier this pane is 'Accessibility')"
echo "  3. quit and reopen the app"
