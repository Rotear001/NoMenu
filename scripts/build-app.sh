#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
APP_DIR="$PROJECT_DIR/build/NoMenu.app"
CONTENTS_DIR="$APP_DIR/Contents"
BUILD_DIR="$PROJECT_DIR/.build"
CACHE_DIR="$PROJECT_DIR/.swiftpm-cache"
MODULE_CACHE_DIR="$PROJECT_DIR/.module-cache"
BUNDLE_IDENTIFIER="com.nomenu.utility"

# Fail before compiling, packaging, or changing any app if signing credentials
# are missing. An unchanged bundle path does NOT stabilize an ad-hoc CDHash DR.
if [[ "$CONFIGURATION" != debug && "$CONFIGURATION" != release ]]; then
    print -u2 'Usage: build-app.sh [debug|release] (both use development signing)'
    exit 1
fi
if [[ -n "${NOMENU_CODE_SIGN_IDENTITY:-}" ]]; then
    print -u2 'NOMENU_CODE_SIGN_IDENTITY overrides are no longer supported. Pin your existing self-signed certificate in Support/DevelopmentSigning.conf.'
    exit 1
fi
IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning)"
source "$PROJECT_DIR/Support/DevelopmentSigning.conf"
if ! print -r -- "$NOMENU_DEVELOPMENT_CERTIFICATE_SHA1" | /usr/bin/grep -Eq '^[A-F0-9]{40}$'; then
    print -u2 'Pin your existing self-signed code-signing certificate SHA-1 in Support/DevelopmentSigning.conf before building.'
    exit 1
fi
SELECTED_IDENTITY="$(print -r -- "$IDENTITIES" | /usr/bin/awk -v fingerprint="$NOMENU_DEVELOPMENT_CERTIFICATE_SHA1" '$2 == fingerprint { print }')"
if [[ -z "$SELECTED_IDENTITY" ]]; then
    print -u2 'The pinned self-signed development identity is unavailable or invalid. Restore access to the same certificate and private key; no fallback identity will be used.'
    exit 1
fi
if [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$PROJECT_DIR/Support/Info.plist")" != "$BUNDLE_IDENTIFIER" ]]; then
    print -u2 'Bundle identifier must remain com.nomenu.utility.'
    exit 1
fi

# Keep a packaging step for the existing Swift Package executable. There is no
# Xcode application target/signature to preserve or re-sign in this project.
# --force replaces only the linker's local executable signature during packaging.
IDENTITY_REQUIREMENT="identifier \"$BUNDLE_IDENTIFIER\" and certificate leaf = H\"$NOMENU_DEVELOPMENT_CERTIFICATE_SHA1\""

if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR"

cd "$PROJECT_DIR"
swift build --disable-sandbox -c "$CONFIGURATION" --scratch-path "$BUILD_DIR" --cache-path "$CACHE_DIR"
BIN_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" --scratch-path "$BUILD_DIR" --cache-path "$CACHE_DIR" --show-bin-path)"

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/NoMenu" "$CONTENTS_DIR/MacOS/NoMenu"
cp "$PROJECT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/NoMenu.icns" "$CONTENTS_DIR/Resources/NoMenu.icns"
ditto "$PROJECT_DIR/Sources/NoMenu/Resources/en.lproj" "$CONTENTS_DIR/Resources/en.lproj"
ditto "$PROJECT_DIR/Sources/NoMenu/Resources/ko.lproj" "$CONTENTS_DIR/Resources/ko.lproj"
chmod +x "$CONTENTS_DIR/MacOS/NoMenu"

print -r -- "Signing with pinned self-signed development certificate: $NOMENU_DEVELOPMENT_CERTIFICATE_SHA1"
/usr/bin/codesign --force --sign "$NOMENU_DEVELOPMENT_CERTIFICATE_SHA1" --identifier "$BUNDLE_IDENTIFIER" --timestamp=none "$APP_DIR"
/usr/bin/codesign --verify --strict --test-requirement "=$IDENTITY_REQUIREMENT" "$APP_DIR"
# Inspect the generated DR; do not replace it with a weaker custom requirement.
DESIGNATED_REQUIREMENT="$(/usr/bin/codesign -dr - "$APP_DIR" 2>&1)"
if print -r -- "$DESIGNATED_REQUIREMENT" | /usr/bin/grep -q 'cdhash'; then
    print -u2 'Refusing a build with a CDHash-based designated requirement.'
    exit 1
fi
print -r -- "$DESIGNATED_REQUIREMENT"

echo "$APP_DIR"
