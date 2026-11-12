#!/bin/zsh
# Builds Applight.app into ./build. Pass "install" to copy it to /Applications and relaunch.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/Applight.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Applight "$APP/Contents/MacOS/Applight"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# A stable identity keeps the Accessibility grant valid across rebuilds; ad-hoc signing breaks it every time.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x Applight && sleep 1 || true
    rm -rf /Applications/Applight.app
    cp -R "$APP" /Applications/Applight.app
    open /Applications/Applight.app
    echo "Installed and launched /Applications/Applight.app"
fi
