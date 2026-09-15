#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_PATH="$PROJECT_DIR/build/NoMenu.app"

"$PROJECT_DIR/scripts/build-app.sh" debug

test -x "$APP_PATH/Contents/MacOS/NoMenu"
plutil -lint "$APP_PATH/Contents/Info.plist"
plutil -extract LSUIElement raw "$APP_PATH/Contents/Info.plist" | grep -q true
plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist" | grep -q '^com\.nomenu\.utility$'
plutil -extract CFBundleIconFile raw "$APP_PATH/Contents/Info.plist" | grep -q '^NoMenu\.icns$'
test -f "$APP_PATH/Contents/Resources/NoMenu.icns"
cmp "$PROJECT_DIR/Resources/NoMenu.icns" "$APP_PATH/Contents/Resources/NoMenu.icns"
codesign --verify --strict --test-requirement '=identifier "com.nomenu.utility"' "$APP_PATH"

if rg -q 'AXUIElementSetAttributeValue|CGSSetWindow|SLSSetWindow|SkyLight' "$PROJECT_DIR/Sources"; then
    echo "Forbidden external menu-bar mutation API found in Sources." >&2
    exit 1
fi

echo "NoMenu build and bundle smoke check passed."
