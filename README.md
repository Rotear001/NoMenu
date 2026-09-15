# NoMenu

**English** | [한국어](README.ko.md)

NoMenu is a macOS utility for reaching menu bar items that become inaccessible when there is not enough usable menu bar space. It discovers real status items through Accessibility and presents confirmed overflowed items in its own menu bar panel.

> [!IMPORTANT]
> NoMenu was designed for the menu bar behavior of macOS releases before macOS 27. macOS 27 introduced native menu bar overflow handling and changed the behavior on which NoMenu's detection depends. macOS 27 and later are therefore unsupported.

Source-build instructions are provided below. Prebuilt DMG downloads will use GitHub Releases when available.

## Download

No public DMG is currently available.

> Future prebuilt DMG downloads will be published through [GitHub Releases](https://github.com/Rotear001/NoMenu/releases), the canonical binary download location.

Before downloading a future release, note that NoMenu targets macOS 15–26 and does not support macOS 27 or later. The signing and notarization status of each binary will be stated in its release notes.

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

2. Create your own local signing identity as described in [Local code signing](#local-code-signing), then check it:

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

## Local code signing

NoMenu uses a stable local signing identity during development because Accessibility and other privacy-controlled APIs are associated with the application's code identity. Reusing the same locally created identity across rebuilds can reduce repeated TCC identity changes.

Each developer must create and keep their **own** certificate and private key. Certificates with the same display name are still different certificates; do not download or import another developer's identity.

To create the identity with Keychain Access:

1. Open **Keychain Access**.
2. Open **Certificate Assistant** and choose **Create a Certificate**.
3. Set the name to **NoMenu Local Code Signing**.
4. Set **Identity Type** to **Self Signed Root**.
5. Set **Certificate Type** to **Code Signing**.
6. Store the new identity in your login keychain.
7. Reuse that same locally created identity for future NoMenu development builds.

Verify it with either command:

```sh
./scripts/check-local-signing.sh
security find-identity -v -p codesigning
```

The helper only inspects valid signing identities. It does not create, import, export, or change trust for certificates and private keys. It also refuses missing or duplicate same-named identities rather than choosing ambiguously.

The local identity is not Apple Developer ID signing, notarization, Gatekeeper approval, public trust, or Apple verification. Never share or commit private keys, Keychain exports, `.p12` files, PEM private keys, signing passwords, or machine-local signing configuration.

## DMG and distribution notes

Developers can package an already-built app locally with:

```sh
./scripts/package-dmg.sh
```

The script reads the real app version and produces `dist/NoMenu-<version>.dmg`, containing only `NoMenu.app` and an Applications shortcut. DMGs and app bundles are ignored by Git and must not be committed to normal repository history.

A local/self-signed DMG is not Apple-notarized, Developer ID signed, Apple verified, or automatically trusted by Gatekeeper. If macOS blocks a future non-notarized release, use Apple's normal per-app approval workflow—Control-click the app and choose **Open**, or review it in **System Settings › Privacy & Security**. Do not disable Gatekeeper, SIP, or other macOS security protections.

Public DMGs belong in [GitHub Releases](https://github.com/Rotear001/NoMenu/releases) as `NoMenu-<version>.dmg` assets. Creating and publishing a release is a separate distribution task; the repository's local development certificate and private key must never be included.

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

## Contributing

The project is currently in maintenance/finalization status. Focused reports or changes for its pre-macOS 27 behavior are welcome, but support for macOS 27 and later is not an active development goal.
