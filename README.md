# NoMenu

**English** | [한국어](README.ko.md)

NoMenu is a macOS utility for reaching menu bar items that become inaccessible when there is not enough usable menu bar space. It discovers real status items through Accessibility and presents confirmed overflowed items in its own menu bar panel.

> [!IMPORTANT]
> NoMenu was designed for the menu bar behavior of macOS releases before macOS 27. macOS 27 introduced native menu bar overflow handling and changed the behavior on which NoMenu's detection depends. macOS 27 and later are therefore unsupported.

Source-build instructions are provided below. The current prebuilt DMG is available from GitHub Releases.

## Download

**NoMenu 1.0 is now available as a DMG.**

[Download NoMenu 1.0 from GitHub Releases](https://github.com/Rotear001/NoMenu/releases/latest)

The GitHub Releases page is the canonical download location. The current asset is `NoMenu-1.0.dmg` (tag `v1.0`).

Installation:

1. Download `NoMenu-1.0.dmg`.
2. Open the DMG.
3. Drag NoMenu to Applications.
4. Launch NoMenu from Applications.

> **Compatibility**
>
> NoMenu is designed for macOS 15–26.
> macOS 27 and later are not supported.

This build uses a local self-signed code-signing identity. It is not Apple Developer ID signed or notarized, so macOS may require its normal manual per-app approval workflow. Do not disable Gatekeeper, SIP, or other macOS security protections.

SHA-256 for `NoMenu-1.0.dmg`:

```text
3f424e29f60e802de6ad003717fb4b3652cc5ef26050d488fb4844735b408e38
```

## Project status

NoMenu is in maintenance/finalization status. Its original problem is largely handled by macOS 27's native overflow behavior, so active feature development for macOS 27 and later is not planned.

## Features

- Discovers menu bar items exposed by running applications through macOS Accessibility.
- Classifies items as visible, overflowed, or unknown using Accessibility geometry, display safe areas, the active application's menu extent, and on-screen compositor evidence. Only confirmed overflowed items are shown.
- Interacts with supported items through their Accessibility actions. When an accessible menu tree is available, NoMenu presents a native proxy menu and invokes the corresponding real menu actions.
- Supports direct switching between discovered items while interacting with the panel.
- Orders items by menu bar position, recent use, or name.
- Provides ignored-item controls, a global keyboard shortcut, hover behavior, Escape-to-close, and an option to keep the panel open after activation.
- Provides configurable panel position, width, size, spacing, background, blur, transparency, interface scale, animations, and English or Korean UI.
- Manages Launch at Login with `SMAppService`.
- Provides ScreenCaptureKit-based Live Artwork with configurable frame rate and app-icon fallback. Live Artwork depends on capture permission and suitable on-screen pixels.

## Compatibility

| | Support |
| --- | --- |
| Deployment target | macOS 15.0 |
| macOS 15–26 | Target platform for NoMenu's original menu bar behavior |
| macOS 27 and later | Unsupported |

The deployment target is defined in both `Package.swift` and `Support/Info.plist`. It is a build target, not a claim that every macOS 15–26 release and menu bar implementation has been individually validated.

The build helper requires an installed macOS 15–26 SDK and deliberately avoids the macOS 27 SDK. It selects the newest compatible SDK in the active Xcode or Command Line Tools installation.

## Permissions

### Accessibility

Accessibility permission is required to discover menu bar items, read the menu structures they expose, and invoke supported actions. Behavior depends on the information and actions each third-party application makes available through Accessibility.

### Screen Recording

Screen Recording permission is used for Live Artwork and for capturing desktop wallpaper pixels used by the optional panel appearance. Without it, NoMenu falls back to cached artwork or the owning application's icon where possible.

## Privacy

Menu bar discovery, captured artwork processing, and preferences are handled locally. NoMenu does not require an account. The current development build has no configured update-service backend.

## Building from source

NoMenu uses Swift 6 and Swift Package Manager, then packages the executable as an `LSUIElement` application. Install Xcode or Xcode Command Line Tools containing a macOS 15–26 SDK before building.

1. Clone and enter the repository:

   ```sh
   git clone https://github.com/Rotear001/NoMenu.git
   cd NoMenu
   ```

2. Create your own local signing identity as described in [Local Self-Signed Code Signing](#local-self-signed-code-signing), then check it:

   ```sh
   ./scripts/check-local-signing.sh
   ```

3. Build and package the app:

   ```sh
   ./scripts/build-app.sh release
   ```

   The resulting application is `build/NoMenu.app`. The `debug` argument is also accepted; both modes are local development builds.

4. Optionally run the complete build and bundle smoke check:

   ```sh
   ./scripts/verify.sh
   ```

This workflow was verified with Apple Swift 6.4, the macOS 26.5 SDK, and a contributor-owned local signing identity. It does not modify or reset macOS privacy permissions.

## Local Self-Signed Code Signing

### Why local builds use a stable identity

NoMenu uses macOS privacy-controlled functionality such as Accessibility. During local development, repeatedly rebuilding an unsigned app—or signing each build with a different identity—can make its code identity appear different to macOS. Reusing the same contributor-owned local identity helps keep that development identity consistent across builds.

This local identity is only for local development. It is **not** Apple Developer ID signing, Apple notarization, public trust, Apple verification, or a replacement for an official distribution certificate.

### Create your own identity in Keychain Access

Every contributor must create their **own** certificate and private key. Do not download or import another contributor's identity; certificates with the same display name are still cryptographically different identities.

1. Open **Keychain Access**.
2. From the menu bar, choose **Keychain Access → Certificate Assistant → Create a Certificate…**.
3. Set **Name** to `NoMenu Local Code Signing`.
4. Set **Identity Type** to **Self Signed Root**.
5. Set **Certificate Type** to **Code Signing**.
6. Create the identity and store it in your **login** keychain.

A code-signing identity consists of the certificate and its paired private key. Both remain in the login keychain managed by Keychain Access; they do not belong in the repository.

### Verify the identity

Immediately after creating it, confirm that macOS recognizes it as a valid code-signing identity:

```sh
security find-identity -v -p codesigning
```

The output must contain exactly one valid identity named `NoMenu Local Code Signing`. Then run the project-specific check from the repository root:

```sh
./scripts/check-local-signing.sh
```

The identity name is hardcoded in both the signing check and build helper; there is no environment variable for overriding it. The helper selects exactly one valid matching identity. If none exists—or if duplicate valid identities have that name—it exits with an explanation instead of choosing ambiguously.

### Build and verify NoMenu

Build the release configuration from the repository root:

```sh
./scripts/build-app.sh release
```

Before compiling, the build helper runs the signing check and resolves the matching identity's certificate fingerprint internally. It then builds the Swift package, creates the app bundle, signs it with that identity, and verifies its certificate-based designated requirement. A missing or ambiguous identity stops the process before compilation or replacement of the existing app bundle.

The completed app is written to:

```text
build/NoMenu.app
```

Verify the resulting signature and inspect its displayed signing information with:

```sh
codesign --verify --strict --test-requirement '=identifier "com.nomenu.utility"' build/NoMenu.app
codesign -dv --verbose=2 build/NoMenu.app
```

For a complete debug rebuild and bundle smoke check, run:

```sh
./scripts/verify.sh
```

`build-app.sh` accepts `release` or `debug`; both are locally signed development builds. It automatically selects the newest installed macOS 15–26 SDK. `SDKROOT` may select a specific compatible SDK, but it does not configure the signing identity.

### If the identity is missing

Open Keychain Access and confirm that the **login** keychain contains both the `NoMenu Local Code Signing` certificate and its paired private key. If it is absent, create your own identity using the steps above, then rerun `./scripts/check-local-signing.sh`. If the helper reports duplicates, remove or rename the extra identities in Keychain Access before building.

The helper only inspects valid signing identities. It never creates, imports, exports, or changes trust settings for certificates or private keys.

### Never upload local signing material

Never share, commit, attach to a release, or otherwise upload the local signing certificate or identity, its private key, Keychain exports, `.p12`, `.pfx`, `.pem`, or `.key` files, signing passwords, or machine-local signing configuration such as `Support/DevelopmentSigning.conf`.

## DMG and distribution notes

Developers can package an already-built app locally with:

```sh
./scripts/package-dmg.sh
```

The script reads the real app version and produces `dist/NoMenu-<version>.dmg`, containing only `NoMenu.app` and an Applications shortcut. DMGs and app bundles are ignored by Git and must not be committed to normal repository history.

A local/self-signed DMG is not Apple-notarized, Developer ID signed, Apple verified, or automatically trusted by Gatekeeper. If macOS blocks the current non-notarized release or a locally packaged build, use Apple's normal per-app approval workflow—Control-click the app and choose **Open**, or review it in **System Settings › Privacy & Security**. Do not disable Gatekeeper, SIP, or other macOS security protections.

The public `NoMenu-1.0.dmg` is available from [GitHub Releases](https://github.com/Rotear001/NoMenu/releases/latest), the canonical binary download location. Public DMGs are release assets and must not be committed to normal repository history. The repository's local development certificate and private key must never be included.

## Technical notes

NoMenu uses Swift, SwiftUI, AppKit, the macOS Accessibility API, `NSStatusItem`, ScreenCaptureKit, Core Graphics window information, and `SMAppService`.

macOS does not provide a public API that lets one application take ownership of or freely control another application's `NSStatusItem`. NoMenu therefore discovers status items and interacts with the Accessibility interfaces they expose; it does not move, reorder, or take ownership of third-party menu bar items.

The source is organized as follows:

- `Sources/NoMenu/App` — application and panel lifecycle
- `Sources/NoMenu/Services` — discovery, interaction, settings, artwork capture, and shortcuts
- `Sources/NoMenu/Views` and `Sources/NoMenu/Components` — panel and settings UI
- `Sources/NoMenu/Models` — menu item and preference models
- `Resources` and `Support` — application artwork and bundle metadata
- `Tests` — focused source-level checks
- `scripts` — signing checks, build, packaging, verification, and repository-safety tooling

## Known limitations

- macOS 27 and later are unsupported because the operating system handles menu bar overflow differently.
- Discovery and interaction depend on the Accessibility roles, geometry, menus, and actions exposed by each application. Custom menu bar implementations may not be discoverable or fully interactive.
- NoMenu deliberately withholds items whose overflow state cannot be established reliably.
- Screen Recording permission and capturable, composited on-screen pixels are required for Live Artwork; cached artwork or an application icon may be shown instead.
- Public macOS APIs do not expose another application's underlying `NSStatusItem` object.

## Why NoMenu exists

NoMenu began as a way to recover access to status items that could disappear when an application's menus, a display notch, or a constrained layout consumed the available menu bar space. macOS 27 later added native overflow handling, largely superseding that original purpose on newer systems.

## License

NoMenu is available under the MIT License. See [LICENSE](LICENSE) for details.

## Contributing

The project is currently in maintenance/finalization status. Focused reports or changes for its pre-macOS 27 behavior are welcome, but support for macOS 27 and later is not an active development goal.
