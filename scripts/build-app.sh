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
SIGNING_IDENTITY_NAME="NoMenu Local Code Signing"

# Fail before compiling, packaging, or changing any app if signing credentials
# are missing. An unchanged bundle path does NOT stabilize an ad-hoc CDHash DR.
if [[ "$CONFIGURATION" != debug && "$CONFIGURATION" != release ]]; then
    print -u2 'Usage: build-app.sh [debug|release] (both use development signing)'
    exit 1
fi
SIGNING_IDENTITY_SHA1="$("$PROJECT_DIR/scripts/check-local-signing.sh" --print-sha1)"
if [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$PROJECT_DIR/Support/Info.plist")" != "$BUNDLE_IDENTIFIER" ]]; then
    print -u2 'Bundle identifier must remain com.nomenu.utility.'
    exit 1
fi

# Keep a packaging step for the existing Swift Package executable. There is no
# Xcode application target/signature to preserve or re-sign in this project.
# --force replaces only the linker's local executable signature during packaging.
IDENTITY_REQUIREMENT="identifier \"$BUNDLE_IDENTIFIER\" and certificate leaf = H\"$SIGNING_IDENTITY_SHA1\""

select_compatible_sdk() {
    local requested_sdk="${SDKROOT:-}"
    local requested_version
    local requested_major
    if [[ -n "$requested_sdk" ]]; then
        requested_version="$(/usr/bin/plutil -extract Version raw "$requested_sdk/SDKSettings.plist" 2>/dev/null || true)"
        requested_major="${requested_version%%.*}"
        if [[ -z "$requested_version" || "$requested_major" != <-> || "$requested_major" -lt 15 || "$requested_major" -ge 27 ]]; then
            print -u2 'SDKROOT must identify an installed macOS SDK from version 15 through 26.'
            return 1
        fi
        print -r -- "Using macOS SDK $requested_version from SDKROOT."
        return
    fi

    local default_sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
    local sdk_dir="${default_sdk:h}"
    local best_sdk=""
    local best_version=""
    local best_key=0
    local sdk
    local version
    local major
    local minor
    local key
    for sdk in "$sdk_dir"/MacOSX*.sdk(N); do
        version="$(/usr/bin/plutil -extract Version raw "$sdk/SDKSettings.plist" 2>/dev/null || true)"
        major="${version%%.*}"
        minor="${version#*.}"
        [[ "$minor" == "$version" ]] && minor=0
        [[ "$major" == <-> && "$minor" == <-> ]] || continue
        (( major >= 15 && major < 27 )) || continue
        key=$((major * 1000 + minor))
        if (( key > best_key )); then
            best_key=$key
            best_sdk="$sdk"
            best_version="$version"
        fi
    done
    if [[ -z "$best_sdk" ]]; then
        print -u2 'No compatible macOS 15–26 SDK was found in the active developer directory.'
        print -u2 'Select an Xcode or Command Line Tools installation that contains a pre-macOS 27 SDK.'
        return 1
    fi
    export SDKROOT="$best_sdk"
    print -r -- "Using compatible macOS SDK $best_version."
}

select_compatible_sdk
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

print -r -- "Signing with local development identity: $SIGNING_IDENTITY_NAME"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY_SHA1" --identifier "$BUNDLE_IDENTIFIER" --timestamp=none "$APP_DIR"
/usr/bin/codesign --verify --strict --test-requirement "=$IDENTITY_REQUIREMENT" "$APP_DIR"
# Inspect the generated DR; do not replace it with a weaker custom requirement.
DESIGNATED_REQUIREMENT="$(/usr/bin/codesign -dr - "$APP_DIR" 2>&1)"
if print -r -- "$DESIGNATED_REQUIREMENT" | /usr/bin/grep -q 'cdhash'; then
    print -u2 'Refusing a build with a CDHash-based designated requirement.'
    exit 1
fi
print -r -- 'Verified a certificate-based designated requirement.'

echo "$APP_DIR"
