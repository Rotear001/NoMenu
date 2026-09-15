# NoMenu

**English** | [한국어](README.ko.md)

NoMenu is a macOS utility for reaching menu bar items that become inaccessible when there is not enough usable menu bar space. It discovers real status items through the Accessibility API and presents confirmed overflowed items from its own menu bar panel.

> [!IMPORTANT]
> NoMenu was built around the menu bar behavior of macOS releases before macOS 27. macOS 27 introduced native menu bar overflow handling and changed the behavior on which NoMenu's overflow detection depends. As a result, macOS 27 and later are unsupported, and active feature development for those releases is not currently planned.

## Download

No public DMG is currently available.

> Prebuilt DMG downloads will be published through [GitHub Releases](https://github.com/Rotear001/NoMenu/releases) when available. This will be the canonical download location.

Before downloading a future release, note that NoMenu is intended for earlier macOS releases. macOS 27 and later are unsupported because the operating system's native menu bar overflow handling changes the behavior NoMenu relies on.

## Project status and compatibility

NoMenu is a source-only project in maintenance/finalization status. There is no public prebuilt binary release.

| | Support |
| --- | --- |
| Deployment target | macOS 15.0 |
| macOS 15–26 | Target platform for NoMenu's original menu bar behavior |
| macOS 27 and later | Unsupported |

The deployment target comes from both `Package.swift` and `Support/Info.plist`. It is a build target, not a claim that every macOS 15–26 release and menu bar implementation has been individually validated.

## Features

- Discovers menu bar items exposed by running applications through macOS Accessibility.
- Classifies items as visible, overflowed, or unknown using Accessibility geometry, display safe areas, the active application's menu extent, and on-screen compositor evidence. Only confirmed overflowed items are shown.
- Interacts with supported items through their Accessibility actions. When an accessible menu tree is available, NoMenu presents a native proxy menu and invokes the corresponding real menu actions.
- Supports direct switching between discovered items while interacting with the panel.
- Orders items by menu bar position, recent use, or name.
- Provides ignored-item controls, a global keyboard shortcut, hover behavior, Escape-to-close, and an option to keep the panel open after activation.
- Provides configurable panel position, width, size, spacing, background, blur, transparency, interface scale, animations, and English or Korean UI.
- Manages Launch at Login with `SMAppService`.
- Provides ScreenCaptureKit-based Live Artwork with configurable frame rate and app-icon fallback. Live Artwork depends on capture permission and suitable on-screen pixels, so it should be treated as an environment-dependent feature.

## Permissions

### Accessibility

Accessibility permission is required to discover menu bar items, read the menu structures they expose, and invoke supported actions. Behavior depends on the information and actions each third-party application makes available through Accessibility.

### Screen Recording

Screen Recording permission is used for Live Artwork and for capturing desktop wallpaper pixels used by the optional panel appearance. Without it, NoMenu falls back to cached artwork or the owning application's icon where possible.

Menu bar discovery, captured artwork processing, and preferences are handled locally. NoMenu does not require an account. The current development build has no configured update-service backend.

## Building from source

NoMenu is built with Swift 6 and Swift Package Manager, then packaged as an `LSUIElement` application by a shell script. Xcode Command Line Tools or Xcode with a compatible macOS SDK are required.

```sh
git clone https://github.com/Rotear001/NoMenu.git
cd NoMenu
./scripts/build-app.sh release
```

When successful, the packaging script writes `build/NoMenu.app`. The `debug` argument is also accepted; both arguments select Swift optimization settings and both remain local development builds.

Build verification for this snapshot did **not** complete with Apple Swift 6.4 and the macOS 27 SDK: the unchanged source reports compile-time errors in `Sources/NoMenu/Views/SettingsView.swift`. A successful clean build with another toolchain has not been verified, and the source has intentionally not been modified as part of repository publication.

## Development signing

Development used a local self-signed code-signing identity named **NoMenu Local Code Signing** to keep the app's macOS privacy/TCC identity stable across local rebuilds. That certificate, its private key, and the machine-local `Support/DevelopmentSigning.conf` file are not included in the repository.

The packaging script intentionally stops when its pinned local identity is unavailable. A contributor cloning the repository will not have the development identity and will need to configure or adapt signing for their own local environment before producing an app bundle. Changing the signing identity may cause macOS to treat the build as a different application for privacy permissions.

The self-signed identity is for local development only. Any future public binary would need an appropriate distribution process, such as Developer ID signing and notarization; the local certificate must not be imported, shared, or used for public distribution.

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
- `scripts` — packaging, verification, and repository-safety tooling

## Known limitations

- macOS 27 and later are unsupported because the operating system now handles menu bar overflow differently.
- Discovery and interaction depend on the Accessibility roles, geometry, menus, and actions exposed by each application. Custom menu bar implementations may not be discoverable or fully interactive.
- NoMenu deliberately withholds items whose overflow state cannot be established reliably.
- Screen Recording permission and capturable on-screen pixels are required for Live Artwork; cached artwork or an application icon may be shown instead.
- Public macOS APIs do not expose another application's underlying `NSStatusItem` object.
- The current source snapshot has the build-verification limitation described above.

## Why NoMenu exists

NoMenu began as a way to recover access to status items that could disappear when an application's menus, a display notch, or a constrained layout consumed the available menu bar space. macOS 27 later added native overflow handling, largely superseding that original purpose on newer systems.

## Contributing

The project is currently in maintenance/finalization status. Focused reports or changes for its pre-macOS 27 behavior are welcome, but support for macOS 27 and later is not an active development goal.
