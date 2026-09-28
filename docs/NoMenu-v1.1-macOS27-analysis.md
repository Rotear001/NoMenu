# NoMenu v1.1 — macOS 27 compatibility and reliability analysis

Analysis date: 2026-09-28. Source: `main`, commit `9e3fdc4`. Host: macOS 27.0, build 26A428, arm64. Application metadata: NoMenu 1.0, build 1. Minimum deployment target: macOS 15.0 in both `Package.swift` and `Support/Info.plist`.

**Decision: SMALL STRATEGY LAYER NEEDED. A full backend split is not justified by the evidence collected.**

Two actual mismatches were found: native system status items are nested below AX groups that discovery skips, and menu bar rendering is represented by full-width surfaces that the compositor-slot detector rejects. Original third-party AX elements remain discoverable, and one original third-party menu was successfully opened. Preserve the existing interaction and presentation systems.

The empty-panel failure is reproduced. A complete, reliable mapping of native overflow membership is **not yet proven**. In particular, no controlled native expand/collapse cycle was completed. This report distinguishes measurements from inferences and identifies that validation as a prerequisite to implementing a new classifier.

No application source, tests, deployment target, signing configuration, bundle, packaging script, release, or license was edited. Only this report and the accompanying sanitized evidence artifact were added. Temporary observation/build/test files were kept outside the repository.

## 1. Current architecture

### Dependency map

```text
AppDelegate.observeLifecycleChanges / four-second fallback / AX callbacks
  -> AppDelegate.scheduleRefresh / refreshDiscoveredMenuBarItems
  -> MenuBarService.refresh
  -> AccessibilityService.discoverMenuBarItems
       NSWorkspace.runningApplications
       -> each application's AXExtrasMenuBar
       -> direct AXChildren with AXMenuBarItem role / AXMenuExtra subrole
       -> stable identity and retained original AX element
       -> makeScreenGeometries
          + activeApplicationMenuRightEdges
          + discoverCompositorSlots
       -> classify -> MenuBarItem.visibilityState / visibilityReason
  -> MenuBarService.overflowItems
       .overflowed only -> ignored-identity exclusion -> configured sorting
  -> MenuBarPanel -> MenuItemButton / OverflowItemNSButton
  -> MenuItemButton.Coordinator.activate
  -> MenuBarService.beginInteraction / interaction
  -> AccessibilityService.interaction on the retained original AX element
       AX menu snapshot -> confirmed dismissal -> local NSMenu proxy
       OR verified owned popover -> external interaction session
       OR verified AX/focus change -> directPress
  -> AccessibilityService.performMenuAction for proxy commands
```

| Responsibility | Real implementation | Relevant behavior |
|---|---|---|
| Discovery | `Services/AccessibilityService.swift:150`, `discoverMenuBarItems()` | Iterates running applications, reads `AXExtrasMenuBar`, examines only its direct children. Skips NoMenu's own PID and bundle. |
| Identity | Same file, lines 183–194; `Models/MenuBarItem.swift`, `MenuBarItem` | `bundle ID or PID :: AXIdentifier or title :: occurrence`. A cached UUID persists across discovery passes in the same service, not across launches. |
| Original AX retention | `DiscoveryResult.elements`; `MenuBarService.refresh():254` | UUID-to-AX-element map is kept independently of display imagery. |
| Geometry | `AccessibilityService.makeScreenGeometries():488`, `activeApplicationMenuRightEdges():520` | Uses `NSScreen`, display bounds, safe areas, top-right auxiliary region and frontmost application's AX menu extent. |
| Classification | `AccessibilityService.classify():435`, `discoverCompositorSlots():533` | Combines geometry with small window rectangles. Returns `.visible`, `.overflowed`, or `.unknown`. |
| Filtering/order | `Services/MenuBarService.swift:87`, `overflowItems` | Only `.overflowed` and not ignored. No blanket third-party-only, Apple-item, or `isActionable` filter. Sorting uses preference, AX X position, then discovery order. |
| Panel content | `Views/MenuBarPanel.swift:22` | An empty overflow set renders no item controls. There is no separate native-overflow discovery in the view. |
| Panel/window geometry | `App/NoMenuPanel.swift`, `NoMenuPanelController.frameForPanel():392`; `Models/NoMenuBarLayout.swift`, `resolve()` | Selects status-button screen, pointer screen, then fallbacks; computes a screen-relative capsule below the menu bar. |
| Input/routing | `Components/MenuItemButton.swift:95`, `Coordinator.activate`; `OverflowItemNSButton.mouseDown/mouseUp` | Concrete button `representedItem`, target/action rebinding, immutable switch destination, session ownership and stale-result rejection are already stabilized. |
| AX activation/proxy | `AccessibilityService.interaction():249`, `performMenuAction():393`; `MenuBarService.interaction` | Original AXPress; menu snapshot and dismissal; retained action with reopen/path fallback. Popovers require an owned-window change. AXPress support alone does not prove successful interaction. |
| External sessions | `MenuBarService.retainExternalInteraction():357`, `currentExternalWindow`, cancellation paths | Polls verified external windows every 120 ms, with consecutive-miss handling. |
| Artwork | `Services/LiveArtworkCapture.swift`, `ArtworkSourceMapping.sources():178`; `MenuBarService.updateLiveArtwork():161` | ScreenCaptureKit strip plus original owner-PID/window/frame match; falls back to app icon/symbol. Independent of AX routing. |
| Wallpaper | `Services/WallpaperTintProvider.swift` | Captures current desktop pixels with public ScreenCaptureKit, display-local crop, scale-aware dimensions and invalidation guards. |
| Diagnostics/settings | `AppDelegate.swift:427`; `SettingsService`; `SettingsView.swift:1072` | Existing report provider includes counts/permissions/monitors; copy UI already exists. |

There is **no runtime OS compatibility branch** in the discovery/classification/presentation pipeline. The OS-version reads in Settings are informational. `scripts/build-app.sh:31–79` deliberately selects only macOS 15–26 SDKs; this is a build-time SDK policy, not a runtime backend. README currently describes macOS 27 as unsupported.

### Permissions

- Accessibility: required by discovery, AX notifications, original-item activation and proxy commands. Fresh trust checks precede discovery and the interaction pipeline. Denial produces no discovery items and temporary permission polling.
- Screen Recording: used for live icon and wallpaper capture. `CGWindowListCopyWindowInfo` also supplies metadata; the present classification code does not explicitly gate that metadata on Screen Recording permission. Actual window-list availability must be recorded separately from image capture permission.
- Global mouse monitoring/event taps: existing AppKit/CGEvent input infrastructure; the switching tap can consume events. Input Monitoring requirements and permission behavior need separate testing if tap creation fails; this analysis did not request a new permission.
- Login-item registration is an independent Settings/ServiceManagement concern and is not required for menu bar classification.

## 2. macOS 27 observations and runtime evidence

The machine and SDK were checked directly. The installed and development bundles are both version 1.0/build 1 and have different executable hashes. Their exact source provenance cannot be inferred from version metadata. To avoid attributing their behavior to unverified source revisions, a temporary executable compiled the **unchanged current** `AccessibilityService`, `MenuBarItem`, and `MenuBarSymbol` sources and collected their results alongside original AX data and window metadata.

The first sandboxed probe had no real display access and returned `axTrusted=false`, `screenRecording=false`, zero items. Those are sandbox-context results, **not evidence that NoMenu lost permission**. The host observation then reported both permissions true, two displays, and reproduced the app logs. No permission prompt, TCC reset, signing change, item movement, or system setting change was performed. The temporary service installed and removed observers in its own process only; it did not alter the running application's discovery state.

Sanitized machine-readable evidence: [macos27-runtime-evidence.json](macos27-runtime-evidence.json). Coordinates below are global CoreGraphics points with top-left origin, unless explicitly labelled AppKit.

### Display geometry

| Display | CG bounds | AppKit frame | AppKit visible frame | Scale | Safe top / auxiliary right | Current classifier menu band |
|---|---|---|---|---|---|---|
| 1 | `(0,0,1512,982)` | `(0,0,1512,982)` | `(0,0,1512,949)` | 2 | 32 / `(848.5,950,663.5,32)` | `(0,0,1512,37)` |
| 36 | `(1512,103,1135,789)` | `(1512,90,1135,789)` | `(1512,90,1135,789)` | 2 | 0 / absent | `(1512,103,1135,28)` |

The converted safe right region on display 1 is `(848.5,0,663.5,32)`. The current height calculation is `max(status thickness 22, visible gap, 24) + 4`. Thus the external AX item at Y=106.5, height 24 remains within the external computed band.

### Application logs

```text
17:44:08.024 NoMenu[91812] detected items: 9; visible: 0; overflowed: 5; unknown: 4
17:44:10.638 NoMenu[90729] detected items: 9; visible: 0; overflowed: 0; unknown: 9
17:44:12.086 NoMenu[91812] detected items: 9; visible: 0; overflowed: 0; unknown: 9
17:46:34.638 NoMenu[90729] detected items: 8; visible: 0; overflowed: 0; unknown: 8
```

PID 90729 was the development bundle; 91812 was the installed bundle during the observation. Counts changed as the environment changed; they are timestamped snapshots, not an invariant. The initial five overflow results also show why the failure is not simply “27 always produces zero overflow”: earlier geometry conditions can still produce `.overflowed` before compositor evidence is considered.

The non-bundled probe includes NoMenu itself because `Bundle.main.bundleIdentifier` is absent; unlike the real app, it cannot exclude both NoMenu bundles by bundle ID. First raw total: 11, including two NoMenu items; normalized non-NoMenu total: 9. Second raw total: 9, including one NoMenu; normalized total: 8. The evidence artifact removes those probe-only NoMenu rows.

### Representative items

Each original third-party row below exposed `AXMenuBarItem` / `AXMenuExtra`, retained a positive frame and advertised `AXPress`. At the main-display capture the current source classified every listed original item as `.unknown`, with reason `The menu bar is not currently exposed; deferring classification`. Consequently none was eligible for NoMenu's panel.

| Item / stable identity | Bundle / PID | Original AX frame | Screen / native evidence | NoMenu / activation evidence |
|---|---|---|---|---|
| Spotlight; `com.apple.campo::Spotlight::0` | `com.apple.campo` / 2071 | `(1279,4.5,34,24)` | Display 1; native hosted button also reports this frame and Search/Spotlight identity | Unknown; excluded; AXPress advertised, not individually invoked |
| RunCat; `com.kyome.RunCat::RunCat::0` | `com.kyome.RunCat` / 19255 | `(1101,4.5,56,24)` | Display 1; corresponding hosted native button rectangle remains readable | Unknown; excluded; AXPress advertised, not individually invoked |
| NoNoTcH; `com.injisung0818.NoNoTcH::Sparkle Star::0` | `com.injisung0818.NoNoTcH` / 19223 | `(880,4.5,34,24)` | Display 1; collocated with other unavailable items near native overflow anchor. Earlier external-display frame was `(1879,106.5,34,24)` | Unknown; excluded; native AX control clicked through CUA and real Settings/Check for Updates/Restart/Quit menu appeared; no command chosen |
| Dynamic Wallpaper; `whbalzac.Dongtaizhuomian::Dynamic Wallpaper::0` | `whbalzac.Dongtaizhuomian` / 26813 | `(880,4.5,34,24)` | Same main-display frame as NoNoTcH; earlier external frame `(1839,106.5,34,24)` | Unknown; excluded; AXPress advertised; no wallpaper command invoked |
| Screen Mirroring; AXIdentifier `com.apple.menuextra.screen-mirroring` | Native MenuBarAgent / 1049 | `(1067.5,5.5,20.5,22)` in native extras tree | Native system control; Screen Mirroring was present in CUA and a rendered native menu bar surface | Not discovered by NoMenu because its direct parent is `AXGroup`; no actual NoMenu stable ID exists for this row |

The last row supplies a clearly rendered native control. Third-party visibility cannot be certified merely from positive AX frames or the presence of hosted buttons: the duplicated anchor frames are precisely why that inference is unsafe. NoNoTcH supplies a representative custom third-party status item and a successful original-menu activation, not a successful NoMenu proxy-session test.

### Difference A: compositor slot evidence is gone at the expected granularity

Measured on-screen menu bar windows:

```text
window 73473: owner PID 599, layer 24, (0,0,1512,33), onScreen=true
window 74178: owner PID 599, layer 24, (1512,103,1135,30), onScreen=true
```

These are full-width menu bar surfaces. `discoverCompositorSlots` accepts only width 6–400, layer 20–30, height at least 12, and a bounded intersection with a menu band. Both real surfaces fail **only the item-width assumption** among those geometric filters. The large NoNoTcH window also fails width/height, appropriately; it is not a status slot. No valid on-screen small slots were found in the sampled window list.

This proves that the expected per-item compositor evidence is unavailable in this captured macOS 27 state. It does not prove the renderer has no per-item surface under every configuration, or constitute a measured pre-27 comparison.

### Difference B: native system discovery has an extra level

```text
MenuBarAgent, PID 1049
  AXExtrasMenuBar -> AXMenuBar
    AXGroup / AXHostingView, frame (1208,0,22,33)
      AXMenuBarItem / AXMenuExtra
      AXIdentifier = com.apple.menuextra.wifi
      frame = (1208,5.5,22,22)
      actions = [AXShowMenu, AXPress, ...]
    ... similar wrappers for Battery, Clock, Control Center, Screen Mirroring
    AXButton "Show Hidden Menu Bar Items"
```

ControlCenter and SystemUIServer returned `-25212` (`attributeUnsupported`) for their `AXExtrasMenuBar` read in this capture. The actual native extras tree was available through MenuBarAgent. The current service visits that application but discards its direct AX groups before examining their child status elements. This is a confirmed discovery omission, independent of classification.

### Difference C: AX geometry is an anchor, not sufficient visibility evidence

At one main-display capture, NoNoTcH and Dynamic Wallpaper shared `(880,4.5,34,24)`; Surfshark and ChatGPT also shared an overlapping `(882,4.5,24,24)` frame. Native “Show Hidden Menu Bar Items” was observed at `(880.5,1,17.5,30)` in an earlier native snapshot, and `(896.5,1,17.5,30)` later.

**Inference:** items managed by native overflow can preserve plausible, usable positive AX rectangles at/near a shared system anchor instead of an off-screen or notch rectangle. These source frames cannot identify a unique visible slot. The native hidden-items control confirms that native overflow UI exists. However, assigning each collocated item conclusively to native overflow requires a synchronized collapsed/expanded comparison; that comparison was not completed.

MenuBarAgent exposed eight AX window objects across two display rectangles, including repeated bar-sized rectangles and hosted item representations. Some hosted items have `AXButton` roles even while their original application elements remain `AXMenuBarItem` / `AXMenuExtra`. A generic recursive walk over all native windows would risk duplicates and stale/alternate surfaces. Do not substitute those hosted buttons for original activation elements.

### Direct UI validation

The development NoMenu status control was clicked through CUA. Its panel appeared as a capsule with **no item buttons**; the AX window was an empty system dialog. This matches the recorded empty eligibility set. A NoNoTcH original menu subsequently opened through its native AX control and was dismissed. Native overflow expansion, custom-popover ownership, NoMenu proxy actions and physical direct switching were not validated in this empty-panel state.

## 3. First broken assumptions

For the reproduced **third-party empty panel**, the earliest verified bad input is:

```swift
// AccessibilityService.discoverCompositorSlots(), line 545
bounds.width <= 400
```

The system's available menu bar windows are wider, so slot extraction loses the rendered-bar evidence. The consequential wrong condition is:

```swift
// AccessibilityService.classify(), lines 479–480
guard compositorSlots.contains(where: \.isOnScreen) else {
    return (.unknown, "The menu bar is not currently exposed; deferring classification")
}
```

The panel exclusion at `MenuBarService.overflowItems:90` follows the model exactly. It is not the first failure and should not be “fixed” by showing every unknown item.

For **missing native system items**, the earlier failure is `discoverMenuBarItems:178–181`: only direct children are checked, and an `AXGroup` is rejected before its real status child is reached.

**Removing the width limit is insufficient.** A full-width surface overlaps every item and would mark anchor-clamped hidden items visible through `classify:467–477`. The positive frame/coverage tests also cannot identify native overflow membership reliably.

## 4. OS-sensitive assumption inventory and legacy impact

“Before” below means the contract the existing implementation was built around; no pre-27 hardware was available to measure it during this investigation. All current runtime code paths are shared with macOS 15–26.

| File / function | Assumption / why it worked in the existing model | macOS 27 observation or uncertainty | Must change? |
|---|---|---|---|
| `AccessibilityService.discoverMenuBarItems:168–175` | Relevant items belong to an enumerated app with readable extras bar | Most sampled original third-party items still do; native system ownership differs | Preserve primary third-party route; add bounded native interpretation only |
| Same, `:178–181` | Real status elements are direct extras children | Native `AXGroup` wraps real system items | Yes, for native system-item coverage |
| `isRealStatusItem:953` | Original item role is AXMenuBarItem or subrole AXMenuExtra | Sampled original elements satisfy it; hosted render controls can be AXButton | Preserve for original items; do not globally accept all buttons |
| Identity construction `:183–194` | Identifier or title plus occurrence is stable | Identifier-backed examples stable; input-source caption changed between ABC and Korean; identical anchor frames are not identity | Preserve UUID/ownership mechanism; record identity quality; no broad identity rewrite |
| `rectAttribute:1023` | Positive AXPosition/AXSize describe useful menu geometry; zero size yields nil | Original samples have positive frames even at overlapping hidden-item anchors | Keep read function; reinterpret evidence on 27 |
| `classify:446` | Status sizes 4–360 by 8–80 identify a candidate | Representative sources fit; wider/zero-size cases untested | No threshold change justified |
| `classify:449–457` | Off-display or clipped frame means overflow | Native anchor-clamped frames pass; items can change display between snapshots | Preserve legacy; native decision must be per display and synchronized |
| `activeApplicationMenuRightEdges:520` / `classify:459` | Frontmost AX menus bound occupied left area; +2 margin identifies collision | Readable app menu on main display; no synchronized native expanded-state comparison | Native semantics require testing; no new magic threshold |
| `makeScreenGeometries:495–497` | Visible-frame gap/status thickness describes top menu band | Main gap 33; external gap 0 while a 30-point bar exists | Sampled item coverage passes; no geometry replacement proven necessary yet |
| `makeScreenGeometries:498–506` / `classify:462` | Notched displays' entire valid status area is auxiliary top-right region, with 90% coverage | Native UI can use a system anchor and potentially alter layout on expansion | Native classification cannot rely on notch rejection alone; expanded left-side behavior untested |
| `convertToCGCoordinates:511` | AppKit and CG display spaces need explicit local conversion | Two displays have different Y origins; existing conversion matches recorded bounds | Preserve and regression-test offsets/rotation |
| `discoverCompositorSlots:543–548` | Layers 20–30 contain item-sized windows, width at most 400 | Real menu bar surfaces layer 24, width 1512/1135 | Yes, replace native evidence interpretation; retain legacy filters |
| `classify:467–477` | 72% overlap or center containment plus on-screen bit proves an item visible | Full-width surfaces cover many items and cannot prove individual visibility | Yes on 27; do not relax slot size and reuse this condition |
| `classify:479–485` | No on-screen slot means hidden bar; missing individual slot means overflow | On-screen full bar is filtered out, producing false global unknown | Yes on 27 |
| Same classifier | `kCGWindowIsOnscreen` plus geometry is enough; slot PID/alpha not needed | Native ownership is consolidated; generic overlapping windows could become false evidence | Native must distinguish exposure evidence from item evidence; no legacy rewrite |
| Native overflow UI / `isRealStatusItem` | No extra system width/control participates in classification | “Show Hidden Menu Bar Items” AXButton, no identifier or advertised actions in sample | Account for observed control geometry if reliable; localized label cannot be the sole production contract |
| `MenuBarService.overflowItems:87–118` | Overflow is recoverable old-style state; AX X coordinates encode order | Shared X anchors lose physical order; unknowns omitted by design | Preserve legacy filter/order; native eligibility/order must be supplied centrally if proven |
| `MenuBarPanel:22` | Model supplies complete eligible items | Empty panel reproduced | No view/backend branching needed |
| `NoMenuPanelController.screenForStatusButton:432` | Button-window screen or pointer screen is current; retained screen can be invalidated | Items move between displays; current native bar can have several AX surfaces | Existing display invalidation already covers replacement; no proven panel-placement bug |
| `NoMenuBarLayout.resolve` | Visible-frame top gap positions panel below menu bar | Gap differs by display; no panel-placement failure demonstrated | Preserve |
| `AccessibilityService.interaction:249` / menu parsing and dismissal | Original AXPress opens original menu; tree remains readable/dismissible | NoNoTcH menu opening verified; full NoMenu proxy cycle not yet testable | No routing rewrite justified |
| `ownedWindows:585` / `externalWindowEvidence:612` / `isMenuBarSurface:651` | Custom popover belongs to original PID; bar surfaces are distinguishable by band/height | Native bar ownership differs; custom popup ownership not directly tested | Preserve; separate popover evidence gate before proposing any change |
| `ArtworkSourceMapping.sources:178` | Original PID owns exact on-screen item window, with positive alpha | Full bar belongs to system renderer; per-item owner/rectangle evidence missing | Live crop likely unavailable for affected items; retain icon fallback; do not guess crops |
| Same, `:183–189` | Reason-string checks and notch sides prevent occluded crops | Classification reason text currently controls capture eligibility | If new native reasons are added, audit this coupling explicitly; no cosmetic reason renaming |
| `rebuildObservers:909` | Direct child hashes define topology; moved/resized/destroyed callbacks cover layout | Wrapped native descendants are not subscribed as leaves; add-notification errors discarded | Instrument outcomes; native traversal must target leaves without changing legacy behavior |
| `AppDelegate.refreshStatusItemHighlight:150` / `createStatusItems:197` | Own status-button highlight and mouse action remain AppKit-compatible | SDK adds new expanded-interface sessions; own icon highlight not independently validated | No change without a reproduced own-status-item failure |
| `SettingsService.refreshScreenRecordingStatus` / capture services | Permission and public capture capability can be checked separately from AX | Host probe has both permissions true; missing slot evidence persists | No permission reset or new requirement justified |
| `scripts/build-app.sh.select_compatible_sdk` | Pre-27 SDK can run on newer host while retaining legacy linked behavior | Existing bundles exhibit failure anyway; SDK 27 build encounters missing macro plugin | Preserve build/signing helper during analysis |

Changing any shared classifier condition would affect legacy systems. Keep the old classification body, thresholds, interpretation, filtering and interactions intact behind the legacy selection. Do not make legacy discovery recursively traverse arbitrary AX application trees for symmetry.

## 5. Smallest compatibility boundary and backend decision

**SMALL STRATEGY LAYER NEEDED.** A classifier/environment strategy, plus a bounded native AX-wrapper interpretation, is sufficient as the next design boundary. A classifier alone would fix neither omitted native system elements nor capture-mapping assumptions. A full discovery/activation/presentation backend would duplicate stable machinery without evidence that original third-party routing needs replacement.

Conceptual responsibility, not an implementation commitment:

```text
AccessibilityService retains original identity, AX elements, observers, activation
  legacy: current direct-child enumeration + current classifier unchanged
  macOS 27: bounded native wrapper normalization + native visibility evidence
MenuBarService and panel consume the same resulting item model
```

Select the environment/behavior once at the discovery boundary with narrow availability checking. Views, mouse handlers, direct switching, proxy sessions and panel placement should remain unaware of the OS strategy.

Before implementing native rules, validate positive visibility/overflow evidence on a specific display. Separate **bar exposure** from **individual item exposure**. Preserve original owner identity for actions; native hosting owner must not become the app bundle identity. Deduplicate original/native observations without depending on array order, mutable captions, process names, untranslated descriptions or private attributes.

No new `.systemOverflow`/`.unavailable` state is approved by this pass. Native overflow is visibly a distinct OS capability, but the per-item membership predicate is not yet sufficiently established. Keep `.unknown` for unprovable cases. Add a distinct internal state only if controlled observations establish a repeatable public-API predicate; retain legacy `.overflowed` semantics independently.

## 6. Realistic macOS 27 support target

| Question | Evidence-based answer |
|---|---|
| Discover all relevant third-party items? | The sampled original AX extras remain discoverable. “All” is not established: menu-less apps, terminated owners, helper ownership, custom AX implementations and unavailable attributes still need coverage. |
| Distinguish native overflow items? | Shared-anchor geometry and the native overflow control give useful evidence, but exact membership has not been validated across expansion/displays. A universal guarantee is premature. |
| Equivalent to old `.overflowed`? | Not through the old window-slot predicate. Geometric legacy overflow still occurs in some snapshots, but native-managed items can remain in plausible in-band frames. |
| Activate those items with existing AX/proxy system? | Original menu opening worked for NoNoTcH. AXPress availability was read for other originals. End-to-end native-overflow activation, proxy command execution, dismissal and custom popovers remain unverified. |
| Enough public information? | Enough for original discovery, reading native AX structure and the demonstrated menu opening. No documented universal overflow-membership API was found in the reviewed SDK/docs; completeness remains a validation gate. |
| Does native overflow remove part of NoMenu's role? | It offers native access to crowded status items. NoMenu may still supply its panel, filtering/order and proxy interaction where supported. It should not promise recovery of every item solely because the old state existed. |

A defensible release claim is successful discovery and activation of validated classes of status items, conservative presentation when native overflow is positively identified, fallback artwork and useful diagnostics. Unsupported/unprovable cases must stay explicit. Do not announce full macOS 27 compatibility before the remaining runtime matrix passes.

## 7. Proposed file changes after review

No listed application change has been made.

| File | Proposed scope / condition |
|---|---|
| `Sources/NoMenu/Services/AccessibilityService.swift` | One compatibility selection; bounded native leaf enumeration and observation targets; current legacy classifier/enumeration preserved; record useful source evidence without changing activation functions. |
| New `Sources/NoMenu/Services/MenuBarCompatibilityBehavior.swift` | Small strategy and immutable evidence/value types. Avoid a complete duplicate service/backend. Existing legacy implementation can remain in place rather than being rewritten into a symmetric hierarchy. |
| New `Sources/NoMenu/Services/MacOS27MenuBarEnvironment.swift` | Public AX native-surface interpretation and per-display classification only after expansion/correlation validation. This name is provisional. |
| `Sources/NoMenu/Services/MenuBarService.swift` | Only adapt eligible-item consumption/native ordering if the validated model requires it; cache diagnostic discovery snapshot; keep interaction/session/input code untouched. |
| `Sources/NoMenu/Models/MenuBarItem.swift` | Conditional: only if positive native overflow evidence requires a new state/evidence field. No state expansion merely for naming symmetry. |
| `Sources/NoMenu/Services/LiveArtworkCapture.swift` | Conditional: expose unsupported native source mapping while preserving existing app-icon fallback; no guessed icon crop or capture-architecture replacement. |
| New `Sources/NoMenu/Utilities/NoMenuDiagnosticReport.swift` | Read-only snapshot formatting with explicit privacy allowlist. |
| `Sources/NoMenu/App/AppDelegate.swift:427` | Replace side-effecting diagnostic provider calls with read-only snapshot construction; narrow wake integration only if its missing handling is confirmed necessary. Do not change own status-item input/highlight without runtime evidence. |
| `Sources/NoMenu/Views/SettingsView.swift` and localization files | Optional read-only compatibility/count labels, only if useful. Reuse existing Copy Diagnostic Report; no backend switch setting. |
| New `Tests/MenuBarCompatibilityChecks.swift`, `Tests/DiagnosticReportChecks.swift` | Meaningful recorded-snapshot classification and privacy/non-mutation checks. Keep current regression fixtures. |

No deployment-target, Bundle ID, local signing, Developer ID, notarization, TCC, DMG, GitHub Release or LICENSE change is proposed here. README support claims can be updated after runtime support is established. The test runner's obsolete SDK path can be addressed separately without touching application or signing configuration.

## 8. Reliability review and regression risks

### Existing handling and actual gaps

| Event | Existing coverage | Assessment |
|---|---|---|
| Connect/disconnect, arrangement, resolution, rotation, replacement NSScreen | `NSApplication.didChangeScreenParametersNotification` -> synchronous panel/session/cache invalidation -> 180 ms settled discovery; four-second fallback | Substantial handling already exists. No missing observer demonstrated; preserve it. Hardware transitions not physically exercised in this pass. |
| Active Space change | `NSWorkspace.activeSpaceDidChangeNotification` -> presentation generation reset, transient cleanup and settled discovery | Covered; existing generation regression check passes. Physical multi-Space tests still required. |
| App launch/terminate/activate | Workspace notifications -> debounced discovery | Covered; fallback also rereads. |
| Status-item movement/resize/destruction/children | AX observers plus four-second fallback | Native wrapped leaves omitted; AX notification registration results ignored. Missing telemetry/leaf coverage is a source-confirmed gap, not a proven lost-event failure for every app. |
| Display sleep/wake and session lock/unlock | Panel listens to screens sleep/wake and session activation; stops/restarts artwork visibility | Covered for artwork. Does not explicitly invalidate discovery/geometry. |
| Full system sleep/wake | No `NSWorkspace.willSleepNotification`/`didWakeNotification` discovery/geometry observer | Explicit recovery hook is absent; timer/AX/screen notifications provide eventual recovery. First-click/stale-session failure after wake is not reproduced, so this is a narrow validation candidate, not justification for lifecycle refactoring. |
| Dock/menu-bar preferences, auto-hide and native expansion | No dedicated preference/native-overflow invalidation; four-second discovery rebuilds geometry and frontmost-menu evidence | Event-specific handling absent. Discovery may catch up, but existing `prepare` only lays out a closed panel, so silent geometry changes while open deserve a runtime test. Do not assume a settings notification name or add private listeners. |
| Screen identity replacement | Retained `targetScreen` reset, artwork screen cleared, wallpaper tasks invalidated; new prepare resolves replacement screen | Already explicitly handled. |
| Copy Diagnostic Report | Calls `refreshAccessibilityState` and `refreshScreenRecordingStatus` | **Confirmed non-read-only behavior.** Trust transitions can call pipeline callbacks; permission timer state can change, and published Screen Recording changes can update capture. Replace for the requested read-only diagnostic boundary. |

No hardware rotation, detach, sleep/wake or system preference was forced during analysis. Those remain direct tests to perform with a compatible classifier in place. No nice-to-have panel/input/observer architecture cleanup is included in the proposed scope.

### Regression risks

- **High:** relaxing compositor filters globally would mark hidden native items visible and alter legacy overflow behavior. Preserve the legacy body and prove native predicates with captured inputs.
- **High:** recursing through native application references creates duplicate identities/AX objects and can route to the hosting process. Bound the traversal and retain original activation references.
- **High:** changing sorting when several frames share X could move controls beneath a pointer or invalidate a frozen session. Preserve the current presentation-order freeze and represented-item ownership.
- **Medium:** wrong display or retained native surface yields cross-display classification errors. Record screen association and snapshot freshness; do not use a global “some bar is visible” bit as per-screen evidence.
- **Medium:** unavailable item-sized compositor evidence prevents live icon mapping. Keep fallback imagery rather than capturing another item's pixels.
- **Unproven:** native popover ownership, own status-item highlight, proxy dismissal and direct-switch timing changes. Leave those systems alone until a specific runtime failure proves a necessary change.

The new macOS 27 SDK documents `NSStatusItem.expandedInterfaceDelegate`/session lifecycle for an application's own expanded interface. This is relevant to a possible future own-status-item issue, not evidence that NoMenu's third-party activation must be rewritten. [Apple documentation](https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate). Apple Developer Forums contains beta-era reports about status-item highlight/occlusion changes; those are external reports, not reproduced failures on this build. [Forum thread](https://developer.apple.com/forums/thread/836113).

## 9. Diagnostics design and Settings review

Construct an immutable diagnostic snapshot on the main actor using current state and **read-only** system queries. Format/export that snapshot separately. Copying the resulting text is the only intended external side effect.

```text
NoMenu Diagnostics
Report schema: 1
Version: 1.0
Build: 1
macOS: 27.0 (26A428)
Architecture: arm64
Compatibility behavior: legacy classifier [current implementation]
Snapshot: cached; last discovery age: ...

Displays: 2
Display #1 / runtime ID 1
  CG frame: (0,0,1512,982)
  AppKit frame: (0,0,1512,982)
  Visible frame: (0,0,1512,949)
  Scale: 2; safe top: 32; auxiliary right present: yes
Display #2 / runtime ID 36
  ...

Menu Bar
  Detected: 8; visible: 0; legacy overflow: 0; unknown: 8
  Native overflow: not classified [do not imply zero]
  Ignored detected items: ...; eligible panel items: 0
  Active panel display / discovery menu display: ...
  Menu band and usable regions per display: ...
  Application-menu right edge per display: ... or unavailable
  On-screen bar surfaces: ...; usable legacy compositor slots: 0
  AX native overflow control observed: yes / unavailable
  Refresh suspended: ...; snapshot age: ...

Permissions
  AX runtime trusted: ...; cached trusted: ...
  Screen Recording preflight: ...; cached capture state: ...
  Window metadata read: available / unavailable
  AX observer registration successes/failures: ...
  Event-tap creation state: ...

Runtime
  Panel/session/monitor/observer counts: ...
  Last geometry invalidation reason: ...
```

After a strategy exists, report the automatically selected behavior accurately. Do not label the current code “macOS 27 backend” just because the machine runs 27. Distinguish raw classification counts, ignored detected items and eligible panel counts: the present `overflowItems.count` is already post-ignore filtering.

Basic diagnostics should not enumerate unrelated processes, item titles, file/window titles or app data. For item-level issue evidence, use optional report-local opaque row IDs with sanitized bundle identifiers, roles/subroles, frame, display, classification reason code and AX action availability. Raw `stableIdentity` may contain a mutable or personal AX title; do not export it automatically. Display IDs/frame/scale are safe runtime metadata; avoid display serial numbers and personalized display names.

Never include username, home directory, precise personal file paths, certificates/fingerprints, signing identity summaries, tokens, keys or generic logs. Existing runtime logs contain executable paths and signing summaries elsewhere; a “copy all logs” implementation would violate the proposed allowlist.

Do not call discovery/refresh/restart, trust reconciliation, capture update, permission request/open-settings, TCC mutation, AXPress, system overflow controls, sorting mutation or backend selection from the report provider. `AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()` can be read without routing through state-changing service refresh methods. Cache discovery evidence during normal discovery, not during report generation.

**Settings:** no manual backend selection setting is needed. Reuse Copy Diagnostic Report. Optional read-only compatibility status and clearer counts are sufficient; add them only after support semantics are settled.

## 10. Validation performed, next matrix and public API limits

### Completed checks

| Check | Result / limit |
|---|---|
| Current source inspection and source tree/private-mutation scan | Completed; no SkyLight import, CGS/SLS mutation, binary patching or injection introduced. |
| Host environment and two-display geometry | Directly read on macOS 27.0/arm64. |
| Installed/development discovery logs | Failure reproduced; both reported zero visible and zero overflow after the captured layout change. |
| Unchanged-source AX/classification/window probe | Compiled for macOS 15.0; host read permission true; original status elements and full-width bar surfaces recorded. |
| Development panel | Directly opened; empty capsule and no AX item controls verified. |
| NoNoTcH original menu | Opened through CUA AX control, menu content verified and dismissed; no menu command executed. |
| Full package build with macOS 26.5 SDK selected, macOS 15 target | Passed in temporary scratch/cache directories. No bundle packaging/signing/install step run. Linker reported nonfatal absent optional toolchain search paths. Mach-O `minos=15.0` verified. |
| Build using default macOS 27 SDK | Failed in current Command Line Tools: missing `SwiftUIMacros.StateMacro` plugin for SwiftUI `@State`. This does not establish an application logic failure or a need to change runtime source. |
| Existing regression checks | Eight existing files compiled together against unmodified production sources, excluding app entry, using SDK 26.5 / target macOS 15.0; executed on this macOS 27 host; all assertions passed. |
| macOS 15–26 runtime / Intel runtime | Not performed. No older physical host or VM was available. |

The eight checks were `AccessibilityStateChecks`, `SpaceBehaviorChecks`, `OutsideDismissalChecks`, `ActiveItemToggleChecks`, `LiveArtworkChecks`, `ArtworkMappingChecks`, `BarAppearanceChecks`, and `SettingsContentChecks`. They exercised injected trust/timer lifecycle, Space generations, outside-click classification, session switching/toggle-off, artwork publishing/mapping, layout/wallpaper math, mock login/settings persistence, sorting/ignore behavior and frozen presentation order. These are service/model regressions, not physical Tap to Click or native menu-tracking tests. Settings rendering/real hotkey checks conditional on snapshot environment variables were not enabled.

`Tests/run-settings-checks.swift` hardcodes an unavailable SDK 15.4 path. The existing check bodies were therefore assembled in a temporary harness instead of editing the runner. The package has no SwiftPM test target, and no repository GitHub Actions workflow was found. Package compilation with a modern SDK and deployment target 15 does not replace old-OS runtime validation or a minimum-SDK build.

### Required native runtime matrix before implementation/release claims

1. Controlled native collapse/expand on the notched display and the external display. Record original owner PID/identity, role/subrole, positive/zero frame, AX children/state, native hosted evidence, bar/control geometry, frontmost menu edge and classification in synchronized snapshots. Establish which observations actually prove individual overflow membership.
2. Prove stable identity/deduplication across native expansion, repeated discovery, input-source/title changes, item ordering and moving the active menu bar between displays. Treat repeated native AX surfaces as potentially stale until current-display/exposure evidence confirms them.
3. After review and a minimal classifier implementation: visible/native-overflow/unavailable/ignored items, menu-tree and custom-popover apps, original AXPress, proxy command action, original-menu dismissal, same-item toggle-off, direct switching, highlight and physical mouse/Tap to Click.
4. Connect/disconnect, arrange, resolve/scale, rotate and replace displays; test first click after transition, status hit frame, wallpaper crop and live artwork fallback. Include nonzero and negative display origins and separate-Spaces configurations.
5. Practical sleep/wake and lock/unlock; auto-hide menu bar, Dock/menu bar preferences, active Spaces and full-screen. Verify observers and four-second fallback do not preserve stale eligible sets or sessions.
6. Permission denied/granted/revoked states, absent window metadata, unsupported AX attributes/actions and capture failure. Prove Copy Diagnostic Report has no state/pipeline side effects.

Legacy validation: leave original logic unchanged; add recorded pre-27 input fixtures for all existing classification branches and narrow native fixtures for the new predicate. Re-run the eight checks and available SDK/deployment-target builds; arrange macOS 15/26 runtime coverage in CI or external testing before claiming it. Issue templates should include the read-only report and specific reproduction steps, not generic private logs.

### Public API limitations

- Public AXExtrasMenuBar/AXChildren/AXRole/AXSubrole/AXPosition/AXSize and action APIs remain useful. The observed AX hierarchy is data, not a guaranteed stable menu bar manager protocol. [Apple extrasMenuBar documentation](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/attribute/extrasmenubar).
- `CGWindowListCopyWindowInfo` exposes window metadata, not an item-by-item menu bar visibility contract. Whole-bar window visibility does not reveal which hosted item is rendered. [Apple window-list documentation](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)).
- NSScreen safe/auxiliary areas describe display geometry, not current native overflow membership. [Apple auxiliaryTopRightArea documentation](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea-gr2n).
- `NSStatusItem.isVisible` concerns an application's own status item and can remain true while application menus obscure it; it is not a public cross-process native-overflow flag. The reviewed SDK's expanded-interface delegate is also for the owning application's presentation lifecycle, not discovery of every other item's overflow state.
- The sampled native overflow button had no AXIdentifier and advertised no actions. Its English description alone is neither a localization-safe production discriminator nor proof that AX can programmatically expand it. Diagnostics must never attempt to expand it.
- Native owner/hosted-child representation may differ from the original owning app. No private attributes, process injection, private compositor mutation or binary patching are acceptable substitutes for missing public evidence.

**Stop point reached:** source architecture, concrete failure inputs, legacy impact, narrow boundary, reliability gaps and proposed validation are documented. Runtime implementation remains untouched. Review this decision and the remaining native-membership validation gate before authorizing code changes.
