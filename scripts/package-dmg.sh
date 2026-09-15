#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_PATH="$PROJECT_DIR/build/NoMenu.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
DIST_DIR="$PROJECT_DIR/dist"
BUNDLE_IDENTIFIER="com.nomenu.utility"

if [[ ! -d "$APP_PATH" || -L "$APP_PATH" || ! -f "$INFO_PLIST" ]]; then
    print -u2 'Missing build/NoMenu.app. Run ./scripts/build-app.sh release first.'
    exit 1
fi

ACTUAL_IDENTIFIER="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$INFO_PLIST")"
if [[ "$ACTUAL_IDENTIFIER" != "$BUNDLE_IDENTIFIER" ]]; then
    print -u2 -- "Unexpected bundle identifier: $ACTUAL_IDENTIFIER"
    exit 1
fi

VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
if [[ -z "$VERSION" || "$VERSION" == *[!A-Za-z0-9._-]* ]]; then
    print -u2 'The application version is missing or unsafe for a DMG filename.'
    exit 1
fi

/usr/bin/codesign --verify --strict --test-requirement '=identifier "com.nomenu.utility"' "$APP_PATH"

STAGING_ROOT="$(/usr/bin/mktemp -d /tmp/NoMenu-dmg.XXXXXX)"
cleanup() {
    if [[ "$STAGING_ROOT" == /tmp/NoMenu-dmg.* && -d "$STAGING_ROOT" ]]; then
        /bin/rm -rf -- "$STAGING_ROOT"
    fi
}
trap cleanup EXIT

VOLUME_DIR="$STAGING_ROOT/NoMenu"
/bin/mkdir -p "$VOLUME_DIR" "$DIST_DIR"
/usr/bin/ditto "$APP_PATH" "$VOLUME_DIR/NoMenu.app"
/bin/ln -s /Applications "$VOLUME_DIR/Applications"

OUTPUT_PATH="$DIST_DIR/NoMenu-$VERSION.dmg"
/usr/bin/hdiutil create \
    -volname NoMenu \
    -srcfolder "$VOLUME_DIR" \
    -format UDZO \
    -ov \
    "$OUTPUT_PATH"

print -r -- "Created $OUTPUT_PATH"
/usr/bin/shasum -a 256 "$OUTPUT_PATH"
