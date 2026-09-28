# NoMenu v1.1 — minimal macOS 27 compatibility implementation

Implementation and direct validation: 2026-09-28, macOS 27.0 (26A428), arm64.

The requested compatibility path passes the measured discovery, correspondence, presentation, activation and regression checks. Runtime changes are restricted to two files, **172 added lines / 3 deleted lines**. Input, activation, panel, display/Spaces, deployment and signing configuration were not edited.

The machine had one display for the manual collapsed → expanded → collapsed comparisons. An external display was connected again during final verification; the final rebuilt app was also verified with both displays available. This is an implementation/validation report, separate from the earlier analysis report.

Detailed per-item records: [sanitized evidence](macos27-implementation-evidence.json).

## 1. Exact full-width-window difference

The comparison sequence exposed an on-screen **layer 24**, Window Server PID **599**, CG window **79049**, bounds **(0, 0, 1512, 33)**. These bounds did not change when native overflow was expanded or collapsed. The existing `6...400` width filter rejected this 1512pt window, leaving no per-item compositor slots. The old classifier consequently returned `unknown` for usable collapsed item frames.

The final two-display configuration also exposed an external layer-24 window with bounds **(1512, 103, 1135, 30)**. Its derived legacy menu-bar band was 28pt high. The new validation allows at most 4pt beyond that derived band, capped at 40pt, and still requires the actual AX extras bar's height and vertical position to match the window within 2pt.

The new path requires all of:

- Layer exactly 24; width greater than 400.
- Owner PID equal to the verified system MenuBarAgent PID, or CG owner name exactly `Window Server` (the observed public metadata spelling).
- Width, horizontal origin and top edge matching the associated CG display within 2pt.
- A bounded menu-bar height rather than a display-sized overlay.
- A real `AXExtrasMenuBar` / `AXMenuBar` from `com.apple.MenuBarAgent` at `/System/Library/CoreServices/MenuBarAgent.app`.
- That AX bar's bounds contained in the candidate, with matching top edge and height.
- The candidate actually on screen.

The old compositor-slot function, including `bounds.width <= 400`, is byte-for-byte unchanged. Full-width windows become environment evidence; they are never inserted into the individual-icon slot list. The observed NoNoTcH **640×210**, layer-27 overlay fails the new rule.

## 2. Exact AX group structure

The observed system hierarchy is:

```text
MenuBarAgent application
  AXExtrasMenuBar: AXMenuBar
    AXGroup / AXHostingView
      AXMenuBarItem / AXMenuExtra
```

The original comparison contained Wi-Fi, Battery, Control Center and Clock. Audio/video and screen-mirroring extras appeared later as the recording/display environment changed. They retain the same group shape.

Traversal descends exactly one verified `AXGroup/AXHostingView` level under a real extras `AXMenuBar`. The group must fit the extras bar and intersect a screen's menu-bar band. Only the previously accepted role/subrole predicate is accepted for leaves. Applications, windows, arbitrary groups, child buttons, and Control Center internal controls are not traversed. Structural groups and the native overflow button do not become NoMenu items.

## 3. Effect of native expansion/collapse on hierarchy

The user manually performed every native overflow transition. No automated or synthetic click was sent to Apple's overflow control.

In the first A/B/C sequence, the representative items' original AX paths, roles, subroles and PIDs were unchanged. System items stayed under the same hosting groups. Third-party items stayed under their original owner's direct `AXExtrasMenuBar` child. Hidden items were already exposed through public AX while collapsed.

A direct, actionless `AXButton` at the extras bar's leading edge was present in both states. Its description changed from `Show Hidden Menu Bar Items` to `Hide Menu Bar Items`; its **(887, 1, 17.5, 30)** frame remained unchanged. Production code recognizes the verified structure/geometry, not those localized strings, and never invokes this control.

Hidden original item frames changed; the full-width window and group structure did not:

| Item / PID | Collapsed A frame | Expanded B frame | Collapsed C frame |
| --- | --- | --- | --- |
| Dynamic Wallpaper / 26813 | (871, 4.5, 34, 24) | (610, 4.5, 34, 24) | (871, 4.5, 34, 24) |
| Surfshark / 69560 | (873, 4.5, 24, 24) | (580, 4.5, 24, 24) | (873, 4.5, 24, 24) |
| Desktop Butter / 94545 | (855, −0.5, 50, 34) | (524, −0.5, 50, 34) | (855, −0.5, 50, 34) |
| Sparkle Star / 19223 | (911, 4.5, 34, 24) | unchanged | unchanged |
| RunCat / 19255 | (1015, 4.5, 56, 24) | unchanged | unchanged |

All five third-party paths were `AXExtrasMenuBar/0`, role `AXMenuBarItem`, subrole `AXMenuExtra`. System paths were `AXExtrasMenuBar/<group>/0` with the same accepted role/subrole. Full records include the stable identities and classification/panel eligibility for each measurement.

## 4. Stable identities and deduplication

The existing identity format is retained: `owner bundle (or PID fallback)::AXIdentifier (or existing title fallback)::occurrence`. Examples that survived A/B/C are:

```text
whbalzac.Dongtaizhuomian::Dynamic Wallpaper::0
com.surfshark.vpnclient.macos.direct::연결이 해제됨::0
com.hoppe.desktoppet::Desktop Butter::0
com.injisung0818.NoNoTcH::Sparkle Star::0
com.kyome.RunCat::RunCat::0
com.apple.MenuBarAgent::com.apple.menuextra.wifi::0
```

Correspondence was checked using stable identity **and** PID, original AX path, role and subrole. Matching positions were not used as identity. All recorded snapshots have unique stable identities.

For macOS 27 aliases, discovery checks `CFEqual` within the existing identity base before allocating an occurrence. A repeated reference reuses the already-established identity for its duplicate log and is omitted. Distinct AX elements with the same title/identifier retain separate occurrences; frames and indexes are not deduplication keys.

The input source changed from `ABC` to `2-Set Korean` during the user responses. Its existing title-fallback stable identity changed accordingly. This is an existing identity limitation, independent of overflow expansion; it was not rewritten in this patch.

MenuBarAgent restarted when the external display was connected: comparison PID 1049 became final PID 95629. This later process change is separate from the measured A/B/C sequence and is recorded in the evidence.

## 5. Compatibility boundary and classification semantics

`MenuBarCompatibility.current` contains the patch's single `#available(macOS 27.0, *)` check. Only discovery and classifier evidence consume the mode.

Before macOS 27, discovery uses the original direct children; native environment evidence is empty. The old role predicate, frame/geometry checks, compositor-slot function and classifier's legacy body remain unchanged. A source comparison verified those bodies, and verified the complete existing interaction/AX action routing block is unchanged.

On macOS 27, a verified native bar permits usable AX geometry to resolve as `visible`. An item on the leading side of the verified native overflow boundary resolves as `overflowed`, allowing the existing panel filter to present it. Collapsed items clamp near that boundary; expanded items move farther left but belong to the same managed overflow set. Existing application-menu/notch/clipping checks continue to apply.

Here `overflowed` supplies the existing UI's presentation eligibility for native-overflow-managed items, including while Apple's expansion is open. It does not claim that an expanded native item is currently invisible. No enum cases, backend architecture, or presentation/interaction branches were added.

Development logs use `[NoMenuCompatibility]` and `[NoMenuAXDiscovery]`. Discovery logs are capped at 24 accepted/duplicate entries per pass; window logs at 8 distinct owner/layer/bounds/on-screen combinations per pass. Repeated full-width backing windows do not consume the log with identical entries. Logs are compiled under `DEBUG`.

## 6. Files changed

Runtime:

- [AccessibilityService.swift](../Sources/NoMenu/Services/AccessibilityService.swift): bounded group discovery, identity-aware alias removal, verified native environment evidence and classifier branch.
- [MenuBarCompatibility.swift](../Sources/NoMenu/Services/MenuBarCompatibility.swift): 41-line mode/geometry helper.

Validation/documentation:

- [MenuBarCompatibilityChecks.swift](../Tests/MenuBarCompatibilityChecks.swift): observed positive geometry and negative overlay/owner/layer/display fixtures; native overflow membership across all three states.
- This report and `docs/macos27-implementation-evidence.json`.

The earlier analysis report/evidence remain unchanged. The compatibility implementation did not alter version metadata; the separate release-preparation change updates `Support/Info.plist` to version 1.1, build 2. No unrelated v1.1 feature was added.

## 7. Runtime diff review

Two runtime files, **+172 / −3 lines** total, including the new 41-line file. No service was copied. Exactly one availability boundary was added.

`discoverCompositorSlots`, `makeScreenGeometries`, coordinate conversion, active menu extent and accepted item-role checks remain byte-identical. The interaction/AX activation block also remains byte-identical. No input, proxy session, button binding, panel, screen invalidation, rotation, Spaces, wallpaper, settings, `Package.swift` or signing script changes are present. The separate `Support/Info.plist` release-preparation diff changes only version 1.0/build 1 to version 1.1/build 2. `git diff --check` passes. The original eight check files are unchanged.

## 8. Direct macOS 27 discovery and panel results

The group-only measurement retained the original classifier: collapsed A and C returned 14 `unknown` items. Expanded B returned 3 `overflowed` / 11 `unknown` because some expanded frames already failed legacy geometry checks. This illustrates why expanding the native UI could mask the collapsed-state failure.

The compatibility probe before launching the development app returned **14 discovered / 11 visible / 3 overflowed / 0 unknown** while native overflow was collapsed.

After launching the signed development app, the active menu/recording environment changed. The actual app returned **15 discovered / 9 visible / 6 overflowed / 0 unknown**. CUA inspection of its real panel showed the same six identities in collapsed, expanded and recollapsed states: Desktop Butter, flow, Sparkle Star, Dynamic Wallpaper, Surfshark, ChatGPT. Order varied under the existing sorting behavior; identity membership did not.

After the external display reconnected, the final rebuilt app was normally quit and relaunched as PID **95779**. It returned **16 discovered / 12 visible / 4 overflowed / 0 unknown**. Its actual panel contained Desktop Butter, Sparkle Star, Dynamic Wallpaper and Surfshark. Different active-display/menu geometry and an additional screen-mirroring system extra explain the changed count. The native extras bar was now **(1908.5, 103, 715.5, 30)**, associated with the external full-width window.

Unbundled probes additionally discover the development app's own status item. Evidence therefore supplies both raw probe counts and production-equivalent counts excluding `com.nomenu.utility`; this is why the final raw count is 17 while the real app count is 16.

## 9. Existing activation path

Real NoMenu panel buttons were clicked; no activation/input code was changed. Existing routing logs verified:

| NoMenu item | Expected / actual AX PID | Existing result |
| --- | --- | --- |
| Sparkle Star | 19223 / 19223 | Correct stable target; NoNoTcH proxy menu, 5 root entries |
| Dynamic Wallpaper | 26813 / 26813 | Correct stable target; proxy menu, 17 root entries |
| Surfshark | 69560 / 69560 | Correct stable target; proxy menu, 15 root entries |

The logs connect physical/button stable identity → resolved original AX target → matching PID → proxy owner/final target. Sparkle Star's menu entries included Settings, Check for Updates, Restart NoNoTcH and Quit. Menus were dismissed without selecting commands.

After final rebuilding and relaunching, Sparkle Star was tested again in app PID 95779: the same stable identity, expected/actual PID 19223 and 5-entry `menuTree` result passed. These checks establish readable-menu proxy behavior for representative third-party items. They do not establish every system item's popover behavior.

## 10. Legacy build and regression result

The existing `scripts/build-app.sh debug` selected **macOS SDK 26.5**, built successfully and signed with the unchanged **NoMenu Local Code Signing** identity. The script verified its certificate-based designated requirement. The final executable's Mach-O minimum OS is **15.0**. The relaunched app logged `startup trusted: true`, with no new permission grant needed.

The same eight existing check files ran unmodified against final production sources, using SDK 26.5 and target `arm64-apple-macosx15.0`: **8/8 PASS**.

1. AccessibilityStateChecks
2. SpaceBehaviorChecks
3. OutsideDismissalChecks
4. ActiveItemToggleChecks
5. LiveArtworkChecks
6. ArtworkMappingChecks
7. BarAppearanceChecks
8. SettingsContentChecks

The new compatibility checks also pass, including the 30pt external bar / 28pt derived-band fixture, unrelated full-width owners and layers, a screen-sized overlay, the observed NoNoTcH overlay, wrong display/AX relationships, and observed collapsed/expanded/recollapsed frames.

The standalone checks were assembled in a temporary working directory outside the repository from unchanged production sources (excluding the executable app entry point), the eight existing check bodies and the new check file. With `CHECK_DIR` set to that temporary directory, they were compiled with:

```text
xcrun swiftc -D DEBUG -swift-version 6
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  -target arm64-apple-macosx15.0
  -module-cache-path "$CHECK_DIR/module-cache"
  "$CHECK_DIR/main.swift"
  -o "$CHECK_DIR/run"
```

All 21 individual PASS messages are included in the sanitized evidence. These are supported-configuration checks on the current macOS 27 host; no separate physical macOS 15–26 machine was available for direct runtime testing.

## 11. Remaining public-API limitations

- Public AX exposed the measured hidden items while collapsed, so no user expansion is required for discovery. This does not promise exposure by every third-party implementation.
- Apple's native overflow control exposes neither a stable identifier nor an AX action/state contract in this sample. The compatibility rule uses the observed bounded structural/geometry evidence. Unrecognized native layouts fall back to the original classifier; no private API or forced activation is used.
- The full-width environment verifies a bar's presence, not independent compositor slots for every icon. Per-item decisions therefore retain trustworthy original AX roles/frames and the native overflow region evidence.
- Original app AX extras can follow the active display; the implementation classifies the screen associated with the exposed native AX bar. It does not construct a second per-display backend or infer unseen AX items from CG window geometry.
- Title-fallback identities can change with dynamic captions or input-source changes. Multiple distinct same-identifier items still use the existing occurrence mechanism. Broad identity redesign is outside this patch.
- Supported system extras are discovered through verified hosting groups and classified as visible in these measurements. System popover activation and unreadable/non-menu interaction kinds were not comprehensively exercised; representative third-party readable-menu paths were verified.
- The implementation is grounded in build 26A428's public representation. Future hierarchy/geometry changes require new evidence rather than broadening traversal or accepting arbitrary windows.
