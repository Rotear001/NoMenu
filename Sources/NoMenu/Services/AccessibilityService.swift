import AppKit
import ApplicationServices
import Combine
import OSLog

@MainActor
final class AccessibilityService: ObservableObject {
    struct DiscoveryResult {
        let items: [MenuBarItem]
        let elements: [UUID: AXUIElement]
        let icons: [UUID: NSImage]
    }

    private struct Candidate {
        let item: MenuBarItem
        let element: AXUIElement
    }

    private struct ScreenGeometry {
        let displayID: CGDirectDisplayID
        let bounds: CGRect
        let menuBar: CGRect
        let usableStatusRegions: [CGRect]
        let hasUnsafeTopArea: Bool
    }

    private struct CompositorSlot {
        let bounds: CGRect
        let isOnScreen: Bool
    }

    private struct MenuActionReference {
        let element: AXUIElement
        let sourceElement: AXUIElement
        let path: [Int]
        let targetName: String
    }

    private struct OwnedWindowSnapshot: Equatable {
        let windowID: CGWindowID
        let ownerPID: pid_t
        let bounds: CGRect
        let layer: Int
        let alpha: Double
        let isOnScreen: Bool
        let title: String
    }

    private struct AXInteractionSnapshot: Equatable {
        let childRoles: [String]
        let expanded: Bool?
        let value: String?
        let frontmostPID: pid_t?
    }

    @Published private(set) var isTrusted: Bool
    var onMenuBarChange: (() -> Void)?
    var onTrustChange: ((_ previous: Bool, _ current: Bool) -> Void)?
    var onPermissionRequested: (() -> Void)?

    private var cachedIcons: [String: NSImage] = [:]
    private var cachedItemIDs: [String: UUID] = [:]
    private var actionReferences: [UUID: MenuActionReference] = [:]
    private var observers: [AXObserver] = []
    private var observationSignature: String?
    private let trustProvider: () -> Bool
    private var permissionPollTimer: Timer?
    var isPermissionPolling: Bool { permissionPollTimer?.isValid == true }
    private let logger = Logger(subsystem: "com.nomenu.utility", category: "Accessibility")
    private let interactionLogger = Logger(subsystem: "com.nomenu.utility", category: "Interaction")

    init(trustProvider: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.trustProvider = trustProvider
        let current = trustProvider()
        isTrusted = current
        logger.notice("startup trusted: \(current, privacy: .public); stability build 3")
    }

    @discardableResult
    func refreshAccessibilityState(reason: String) -> Bool {
        defer {
            if reason != "permission wait poll" && reason != "discovery preflight" {
                logger.notice("stability check: \(reason, privacy: .public); trusted=\(self.isTrusted, privacy: .public); polling=\(self.isPermissionPolling, privacy: .public); observers=\(self.observers.count, privacy: .public)")
            }
        }
        let previous = isTrusted
        let current = trustProvider()
        if reason != "permission wait poll" {
            logger.debug("\(reason, privacy: .public); AXIsProcessTrusted(): \(current, privacy: .public)")
        }
        if previous != current { isTrusted = current }
        // Reconcile the timer on EVERY runtime result, including true -> true.
        // Timer lifetime must not depend on a view or a transition callback.
        if current {
            stopPermissionPolling()
        } else {
            beginPermissionPollingIfNeeded()
        }
        guard previous != current else { return current }

        logger.notice("permission transition: \(previous, privacy: .public) -> \(current, privacy: .public)")
        onTrustChange?(previous, current)
        return current
    }

    func beginPermissionPollingIfNeeded() {
        guard !isTrusted, permissionPollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] timer in
            // This timer is installed on the main run loop. Read trust in that
            // callback; do not enqueue stale polling Tasks after invalidation.
            let shouldContinue = MainActor.assumeIsolated {
                guard let self, self.isPermissionPolling else { return false }
                _ = self.refreshAccessibilityState(reason: "permission wait poll")
                return self.isPermissionPolling
            }
            if !shouldContinue { timer.invalidate() }
        }
        permissionPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        logger.notice("started temporary permission poll")
    }

    func stopPermissionPolling() {
        guard let timer = permissionPollTimer else { return }
        timer.invalidate()
        permissionPollTimer = nil
        logger.notice("stopped temporary permission poll")
    }

    func requestPermission() {
        logger.notice("permission requested for running process")
        onPermissionRequested?()
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = refreshAccessibilityState(reason: "permission request returned")
    }

    var observerCount: Int { observers.count }
    func clearArtworkCache() { cachedIcons.removeAll() }

    func stopAccessibilityServices() {
        let hadRuntimeState = !observers.isEmpty || !actionReferences.isEmpty
        clearObservers()
        actionReferences.removeAll()
        if hadRuntimeState {
            logger.notice("stopped AX observers and cleared retained AX actions")
        }
    }

    func discoverMenuBarItems() -> DiscoveryResult {
        // Never retain AX access based on an earlier granted result.
        guard refreshAccessibilityState(reason: "discovery preflight") else {
            stopAccessibilityServices()
            return DiscoveryResult(items: [], elements: [:], icons: [:])
        }

        logger.notice("starting menu bar discovery")

        let screenGeometries = makeScreenGeometries()
        let menuRightEdges = activeApplicationMenuRightEdges(in: screenGeometries)
        let compositorSlots = discoverCompositorSlots(in: screenGeometries)
        var candidates: [Candidate] = []
        var iconsByID: [UUID: NSImage] = [:]
        var observationTargets: [(pid_t, AXUIElement, [AXUIElement])] = []
        var occurrenceCounts: [String: Int] = [:]
        var discoveryOrder = 0

        for application in NSWorkspace.shared.runningApplications where !application.isTerminated {
            guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  application.bundleIdentifier != Bundle.main.bundleIdentifier else { continue }

            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            guard let extrasMenu = elementAttribute(kAXExtrasMenuBarAttribute, from: appElement) else { continue }
            let children = elementArrayAttribute(kAXChildrenAttribute, from: extrasMenu)
            guard !children.isEmpty else { continue }
            observationTargets.append((application.processIdentifier, extrasMenu, children))

            for child in children {
                let role = stringAttribute(kAXRoleAttribute, from: child)
                let subrole = stringAttribute(kAXSubroleAttribute, from: child)
                guard isRealStatusItem(role: role, subrole: subrole) else { continue }

                let title = firstNonEmptyString(
                    attributes: [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute],
                    from: child
                ) ?? application.localizedName ?? "Menu Bar Item"
                let identifier = stringAttribute(kAXIdentifierAttribute, from: child)
                let ownerKey = application.bundleIdentifier ?? "pid:\(application.processIdentifier)"
                let identityBase = "\(ownerKey)::\(identifier ?? title)"
                let occurrence = occurrenceCounts[identityBase, default: 0]
                occurrenceCounts[identityBase] = occurrence + 1
                let identityKey = "\(identityBase)::\(occurrence)"
                let itemID = cachedItemIDs[identityKey] ?? UUID()
                cachedItemIDs[identityKey] = itemID

                let frame = rectAttribute(from: child)
                let appleProvided = isAppleProvided(application)
                let classification = classify(
                    frame: frame,
                    role: role,
                    subrole: subrole,
                    screens: screenGeometries,
                    activeMenuRightEdges: menuRightEdges,
                    compositorSlots: compositorSlots
                )
                let pressSupported = supportsAction(kAXPressAction, on: child)
                let hasMenu = findMenu(from: child) != nil
                let canLaunch = NSRunningApplication(processIdentifier: application.processIdentifier) != nil
                let interactionKind: InteractionKind = hasMenu
                    ? .menuTree
                    : (canLaunch ? .launchOnly : .unsupported)

                let item = MenuBarItem(
                    id: itemID,
                    stableIdentity: identityKey,
                    name: title,
                    bundleIdentifier: application.bundleIdentifier,
                    applicationName: application.localizedName ?? title,
                    type: itemType(title: title, isAppleProvided: appleProvided),
                    symbolName: MenuBarSymbol.name(for: title, bundleIdentifier: application.bundleIdentifier),
                    processIdentifier: application.processIdentifier,
                    isActionable: pressSupported,
                    isAppleProvided: appleProvided,
                    accessibilityFrame: frame,
                    visibilityState: classification.state,
                    visibilityReason: classification.reason,
                    interactionKind: interactionKind,
                    discoveryOrder: discoveryOrder
                )
                discoveryOrder += 1
                candidates.append(Candidate(item: item, element: child))

                if let cachedIcon = cachedIcons[identityKey] {
                    iconsByID[itemID] = cachedIcon
                } else if let icon = application.icon {
                    cachedIcons[identityKey] = icon
                    iconsByID[itemID] = icon
                }
            }
        }

        rebuildObservers(from: observationTargets)
        let items = candidates.map(\.item)
        let elements = Dictionary(uniqueKeysWithValues: candidates.map { ($0.item.id, $0.element) })
        logDiagnostics(items)
        return DiscoveryResult(items: items, elements: elements, icons: iconsByID)
    }

    func interaction(
        for element: AXUIElement,
        targetName: String,
        targetPID: pid_t,
        bundleIdentifier: String?
    ) async -> ItemInteraction {
        guard refreshAccessibilityState(reason: "interaction preflight") else {
            return ItemInteraction(kind: .unsupported, menu: [])
        }

        let sourceRole = stringAttribute(kAXRoleAttribute, from: element) ?? "unknown"
        let sourceSubrole = stringAttribute(kAXSubroleAttribute, from: element) ?? "unknown"
        let sourceActions = actionNames(of: element).joined(separator: ",")
        let sourceFrame = rectAttribute(from: element)
        let beforeAX = interactionSnapshot(of: element)
        let beforeWindows = ownedWindows(for: targetPID)
        interactionLogger.notice(
            "[\(targetName, privacy: .public)] probe pid=\(targetPID, privacy: .public); bundle=\(bundleIdentifier ?? "none", privacy: .public); role=\(sourceRole, privacy: .public); subrole=\(sourceSubrole, privacy: .public); actions=\(sourceActions, privacy: .public); frame=\(String(describing: sourceFrame), privacy: .public); children=\(beforeAX.childRoles.description, privacy: .public); ownedWindowsBefore=\(self.windowSummary(beforeWindows), privacy: .public)"
        )

        if let menu = findReadableMenu(from: element) {
            let nodes = menuNodes(from: menu, sourceElement: element, targetName: targetName)
            logMenuEvidence(menu, targetName: targetName, phase: "already exposed")
            interactionLogger.notice(
                "[\(targetName, privacy: .public)] proxy feasible without opening original menu; root items=\(nodes.count, privacy: .public)"
            )
            return ItemInteraction(kind: .menuTree, menu: nodes)
        }

        guard supportsAction(kAXPressAction, on: element) else {
            interactionLogger.notice("[\(targetName, privacy: .public)] source does not expose AXPress")
            return ItemInteraction(kind: .unsupported, menu: [])
        }

        let pressResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
        interactionLogger.notice(
            "[\(targetName, privacy: .public)] original AXMenuBarItem AXPress result=\(pressResult.rawValue, privacy: .public)"
        )
        guard pressResult == .success else {
            return ItemInteraction(kind: .unsupported, menu: [])
        }

        var detectedMenu: AXUIElement?
        var detectedWindow: ExternalWindowEvidence?
        var afterWindows = beforeWindows
        for _ in 0..<25 {
            if let menu = findReadableMenu(from: element) {
                detectedMenu = menu
                break
            }
            afterWindows = ownedWindows(for: targetPID)
            if detectedWindow == nil {
                detectedWindow = externalWindowEvidence(
                    before: beforeWindows,
                    after: afterWindows,
                    ownerPID: targetPID
                )
            }
            try? await Task.sleep(for: .milliseconds(20))
        }

        let afterAX = interactionSnapshot(of: element)
        afterWindows = ownedWindows(for: targetPID)
        if detectedWindow == nil {
            detectedWindow = externalWindowEvidence(
                before: beforeWindows,
                after: afterWindows,
                ownerPID: targetPID
            )
        }
        interactionLogger.notice(
            "[\(targetName, privacy: .public)] probe after AXMenu=\(detectedMenu != nil, privacy: .public); children=\(afterAX.childRoles.description, privacy: .public); frontmostPID=\(String(describing: afterAX.frontmostPID), privacy: .public); ownedWindowsAfter=\(self.windowSummary(afterWindows), privacy: .public)"
        )

        if let externalWindow = detectedWindow, detectedMenu == nil {
            interactionLogger.notice(
                "[\(targetName, privacy: .public)] probe result=customPopover; windowID=\(externalWindow.windowID, privacy: .public); ownerPID=\(externalWindow.ownerPID, privacy: .public); frame=\(String(describing: externalWindow.bounds), privacy: .public); layer=\(externalWindow.layer, privacy: .public); title=\(externalWindow.title, privacy: .public)"
            )
            return ItemInteraction(
                kind: .customPopover,
                menu: [],
                externalWindow: externalWindow
            )
        }

        guard let menu = detectedMenu else {
            if beforeAX != afterAX {
                interactionLogger.notice(
                    "[\(targetName, privacy: .public)] probe result=directPress; verified AX/focus state change"
                )
                return ItemInteraction(kind: .directPress, menu: [])
            }
            interactionLogger.notice(
                "[\(targetName, privacy: .public)] probe result=unsupported; AXPress succeeded but produced no AXMenu, owned window, or AX state change"
            )
            return ItemInteraction(kind: .unsupported, menu: [])
        }

        logMenuEvidence(menu, targetName: targetName, phase: "opened for snapshot")
        let nodes = menuNodes(from: menu, sourceElement: element, targetName: targetName)
        guard !nodes.isEmpty else {
            _ = await dismissOriginalMenu(menu, sourceElement: element, targetName: targetName)
            return ItemInteraction(kind: .unsupported, menu: [])
        }

        // Never hand the tree to the native NoMenu presenter until the original
        // application's menu has completed its AX dismissal. This prevents the
        // original menu-tracking session from swallowing or displacing NSMenu.popUp.
        guard await dismissOriginalMenu(menu, sourceElement: element, targetName: targetName) else {
            interactionLogger.error(
                "[\(targetName, privacy: .public)] refusing proxy presentation because original menu dismissal was not confirmed"
            )
            return ItemInteraction(kind: .unsupported, menu: [])
        }

        interactionLogger.notice(
            "[\(targetName, privacy: .public)] original menu dismissed; proxy ready with \(nodes.count, privacy: .public) root items"
        )
        return ItemInteraction(kind: .menuTree, menu: nodes)
    }

    func currentExternalWindow(
        matching evidence: ExternalWindowEvidence
    ) -> ExternalWindowEvidence? {
        guard let snapshot = ownedWindows(for: evidence.ownerPID)[evidence.windowID],
              snapshot.isOnScreen,
              snapshot.alpha > 0.01 else { return nil }
        return makeExternalWindowEvidence(from: snapshot)
    }

    @discardableResult
    func dismissExternalInteraction(
        for element: AXUIElement,
        evidence: ExternalWindowEvidence,
        targetName: String
    ) -> Bool {
        guard currentExternalWindow(matching: evidence) != nil else { return true }
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        interactionLogger.notice(
            "[\(targetName, privacy: .public)] closing verified external interaction with one AXPress; result=\(result.rawValue, privacy: .public); windowID=\(evidence.windowID, privacy: .public)"
        )
        return result == .success
    }

    func performMenuAction(_ actionID: UUID) async -> Bool {
        guard refreshAccessibilityState(reason: "menu action preflight") else { return false }
        guard let reference = actionReferences[actionID] else { return false }
        let directResult = AXUIElementPerformAction(reference.element, kAXPressAction as CFString)
        interactionLogger.notice(
            "[\(reference.targetName, privacy: .public)] retained AXMenuItem action result=\(directResult.rawValue, privacy: .public); path=\(reference.path.description, privacy: .public)"
        )
        if directResult == .success {
            return true
        }

        let reopenResult = AXUIElementPerformAction(reference.sourceElement, kAXPressAction as CFString)
        guard reopenResult == .success else { return false }
        guard let menu = await waitForReadableMenu(from: reference.sourceElement),
              let currentElement = element(at: reference.path, in: menu) else {
            if let menu = findMenu(from: reference.sourceElement) {
                _ = await dismissOriginalMenu(
                    menu,
                    sourceElement: reference.sourceElement,
                    targetName: reference.targetName
                )
            }
            return false
        }
        let result = AXUIElementPerformAction(currentElement, kAXPressAction as CFString) == .success
        interactionLogger.notice(
            "[\(reference.targetName, privacy: .public)] refreshed AXMenuItem action success=\(result, privacy: .public); path=\(reference.path.description, privacy: .public)"
        )
        if !result {
            _ = await dismissOriginalMenu(
                menu,
                sourceElement: reference.sourceElement,
                targetName: reference.targetName
            )
        }
        return result
    }

    func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private func classify(
        frame: CGRect?,
        role: String?,
        subrole: String?,
        screens: [ScreenGeometry],
        activeMenuRightEdges: [CGDirectDisplayID: CGFloat],
        compositorSlots: [CompositorSlot]
    ) -> (state: MenuBarVisibilityState, reason: String) {
        guard isRealStatusItem(role: role, subrole: subrole), let frame else {
            return (.unknown, "No reliable AX status-item frame")
        }
        guard frame.width >= 4, frame.width <= 360, frame.height >= 8, frame.height <= 80 else {
            return (.unknown, "AX frame is not menu-bar sized")
        }
        guard let screen = screens.first(where: {
            $0.bounds.insetBy(dx: -2, dy: -2).contains(CGPoint(x: frame.midX, y: frame.midY)) ||
            $0.menuBar.intersects(frame)
        }) else {
            return (.overflowed, "AX frame is outside every active display menu bar")
        }

        guard coverage(of: frame, by: screen.menuBar) >= 0.80 else {
            return (.overflowed, "AX frame is clipped outside the menu-bar bounds")
        }
        if let menuEdge = activeMenuRightEdges[screen.displayID], frame.minX < menuEdge + 2 {
            return (.overflowed, "AX frame overlaps the active application's menu extent")
        }
        if screen.hasUnsafeTopArea,
           !screen.usableStatusRegions.contains(where: { coverage(of: frame, by: $0) >= 0.90 }) {
            return (.overflowed, "AX frame intersects the display's unsafe/notch area")
        }

        let matchingSlots = compositorSlots.filter { slot in
            let intersection = slot.bounds.intersection(frame)
            let overlap = frame.width * frame.height > 0
                ? (intersection.width * intersection.height) / (frame.width * frame.height)
                : 0
            let surroundsCenter = slot.bounds.insetBy(dx: -2, dy: -2)
                .contains(CGPoint(x: frame.midX, y: frame.midY))
            return overlap >= 0.72 || surroundsCenter
        }
        if matchingSlots.contains(where: \.isOnScreen) {
            return (.visible, "Usable geometry and a matching on-screen menu-bar compositor slot")
        }
        guard compositorSlots.contains(where: \.isOnScreen) else {
            return (.unknown, "The menu bar is not currently exposed; deferring classification")
        }
        if !matchingSlots.isEmpty {
            return (.overflowed, "Matching menu-bar compositor slot is not on screen")
        }
        return (.overflowed, "No matching visible compositor slot for this real AX status item")
    }

    private func makeScreenGeometries() -> [ScreenGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let bounds = CGDisplayBounds(displayID)
            let visibleGap = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let menuBarHeight = max(NSStatusBar.system.thickness, visibleGap, 24)
            let menuBar = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: menuBarHeight + 4)
            let auxiliaryRightArea = screen.auxiliaryTopRightArea ?? .zero
            let hasUnsafeTopArea = screen.safeAreaInsets.top > 0 && !auxiliaryRightArea.isEmpty
            let rightArea = convertToCGCoordinates(auxiliaryRightArea, screen: screen, displayBounds: bounds)
            return ScreenGeometry(
                displayID: displayID,
                bounds: bounds,
                menuBar: menuBar,
                usableStatusRegions: hasUnsafeTopArea ? [rightArea] : [menuBar],
                hasUnsafeTopArea: hasUnsafeTopArea
            )
        }
    }

    private func convertToCGCoordinates(_ rect: CGRect, screen: NSScreen, displayBounds: CGRect) -> CGRect {
        CGRect(
            x: displayBounds.minX + rect.minX - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func activeApplicationMenuRightEdges(in screens: [ScreenGeometry]) -> [CGDirectDisplayID: CGFloat] {
        guard let activeApplication = NSWorkspace.shared.frontmostApplication else { return [:] }
        let appElement = AXUIElementCreateApplication(activeApplication.processIdentifier)
        guard let menuBar = elementAttribute(kAXMenuBarAttribute, from: appElement) else { return [:] }
        var result: [CGDirectDisplayID: CGFloat] = [:]
        for child in elementArrayAttribute(kAXChildrenAttribute, from: menuBar) {
            guard let frame = rectAttribute(from: child),
                  let screen = screens.first(where: { $0.menuBar.intersects(frame) }) else { continue }
            result[screen.displayID] = max(result[screen.displayID] ?? screen.bounds.minX, frame.maxX)
        }
        return result
    }

    private func discoverCompositorSlots(in screens: [ScreenGeometry]) -> [CompositorSlot] {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return windows.compactMap { info in
            guard let boundsDictionary = info[kCGWindowBounds as String] as? [CFString: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  (20...30).contains(layer),
                  bounds.width >= 6,
                  bounds.width <= 400,
                  bounds.height >= 12,
                  screens.contains(where: { screen in
                      bounds.intersects(screen.menuBar) && bounds.height <= screen.menuBar.height + 20
                  }) else { return nil }
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            return CompositorSlot(bounds: bounds, isOnScreen: isOnScreen)
        }
    }

    private func coverage(of frame: CGRect, by region: CGRect) -> CGFloat {
        let intersection = frame.intersection(region)
        let area = frame.width * frame.height
        return area > 0 ? (intersection.width * intersection.height) / area : 0
    }

    private func interactionSnapshot(of element: AXUIElement) -> AXInteractionSnapshot {
        let childRoles = elementArrayAttribute(kAXChildrenAttribute, from: element).map {
            stringAttribute(kAXRoleAttribute, from: $0) ?? "unknown"
        }
        return AXInteractionSnapshot(
            childRoles: childRoles,
            expanded: boolAttribute(kAXExpandedAttribute, from: element),
            value: scalarAttributeDescription(kAXValueAttribute, from: element),
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
    }

    private func scalarAttributeDescription(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func ownedWindows(for ownerPID: pid_t) -> [CGWindowID: OwnedWindowSnapshot] {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [:] }

        return Dictionary(uniqueKeysWithValues: windows.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownerPID,
                  let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDictionary = info[kCGWindowBounds as String] as? [CFString: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue else {
                return nil
            }
            let snapshot = OwnedWindowSnapshot(
                windowID: windowID,
                ownerPID: ownerPID,
                bounds: bounds,
                layer: layer,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                isOnScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
                title: info[kCGWindowName as String] as? String ?? ""
            )
            return (windowID, snapshot)
        })
    }

    private func externalWindowEvidence(
        before: [CGWindowID: OwnedWindowSnapshot],
        after: [CGWindowID: OwnedWindowSnapshot],
        ownerPID: pid_t
    ) -> ExternalWindowEvidence? {
        let candidates = after.values.filter { window in
            guard window.ownerPID == ownerPID,
                  window.isOnScreen,
                  window.alpha > 0.01,
                  window.bounds.width >= 40,
                  window.bounds.height >= 24,
                  !isMenuBarSurface(window.bounds) else { return false }
            guard let previous = before[window.windowID] else { return true }
            return !previous.isOnScreen ||
                previous.alpha <= 0.01 ||
                !previous.bounds.equalTo(window.bounds)
        }
        guard let best = candidates.max(by: { lhs, rhs in
            let lhsArea = lhs.bounds.width * lhs.bounds.height
            let rhsArea = rhs.bounds.width * rhs.bounds.height
            if lhs.layer != rhs.layer { return lhs.layer < rhs.layer }
            return lhsArea < rhsArea
        }) else { return nil }
        return makeExternalWindowEvidence(from: best)
    }

    private func makeExternalWindowEvidence(
        from snapshot: OwnedWindowSnapshot
    ) -> ExternalWindowEvidence {
        ExternalWindowEvidence(
            windowID: snapshot.windowID,
            ownerPID: snapshot.ownerPID,
            bounds: snapshot.bounds,
            appKitBounds: appKitFrame(from: snapshot.bounds),
            layer: snapshot.layer,
            title: snapshot.title
        )
    }

    private func isMenuBarSurface(_ bounds: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber else { return false }
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            let menuBarBand = CGRect(
                x: displayBounds.minX,
                y: displayBounds.minY,
                width: displayBounds.width,
                height: max(NSStatusBar.system.thickness + 8, 32)
            )
            return bounds.height <= 80 && bounds.intersects(menuBarBand)
        }
    }

    private func appKitFrame(from cgFrame: CGRect) -> CGRect {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber else { continue }
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard displayBounds.intersects(cgFrame) else { continue }
            return CGRect(
                x: screen.frame.minX + cgFrame.minX - displayBounds.minX,
                y: screen.frame.maxY - (cgFrame.maxY - displayBounds.minY),
                width: cgFrame.width,
                height: cgFrame.height
            )
        }
        return cgFrame
    }

    private func windowSummary(
        _ windows: [CGWindowID: OwnedWindowSnapshot]
    ) -> String {
        windows.values.sorted { $0.windowID < $1.windowID }.map {
            "id=\($0.windowID),on=\($0.isOnScreen),frame=\($0.bounds),layer=\($0.layer),alpha=\($0.alpha),title=\($0.title)"
        }.joined(separator: " | ")
    }

    private func findReadableMenu(from sourceElement: AXUIElement) -> AXUIElement? {
        guard let menu = findMenu(from: sourceElement),
              !elementArrayAttribute(kAXChildrenAttribute, from: menu).isEmpty else { return nil }
        return menu
    }

    private func waitForReadableMenu(from sourceElement: AXUIElement) async -> AXUIElement? {
        for _ in 0..<25 {
            if let menu = findReadableMenu(from: sourceElement) { return menu }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    private func menuNodes(
        from menu: AXUIElement,
        sourceElement: AXUIElement,
        targetName: String
    ) -> [ProxyMenuNode] {
        parseMenu(
            menu,
            sourceElement: sourceElement,
            targetName: targetName,
            path: []
        )
    }

    private func findMenu(from element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth <= 4 else { return nil }
        if stringAttribute(kAXRoleAttribute, from: element) == kAXMenuRole { return element }
        for child in elementArrayAttribute(kAXChildrenAttribute, from: element) {
            if let menu = findMenu(from: child, depth: depth + 1) { return menu }
        }
        return nil
    }

    private func parseMenu(
        _ menu: AXUIElement,
        sourceElement: AXUIElement,
        targetName: String,
        path: [Int]
    ) -> [ProxyMenuNode] {
        elementArrayAttribute(kAXChildrenAttribute, from: menu).enumerated().compactMap { index, child in
            let childPath = path + [index]
            let role = stringAttribute(kAXRoleAttribute, from: child)
            let subrole = stringAttribute(kAXSubroleAttribute, from: child)
            let roleDescription = stringAttribute(kAXRoleDescriptionAttribute, from: child)
            let title = stringAttribute(kAXTitleAttribute, from: child) ?? ""
            let descendants = elementArrayAttribute(kAXChildrenAttribute, from: child)
            let submenu = descendants.first(where: {
                stringAttribute(kAXRoleAttribute, from: $0) == kAXMenuRole
            })
            let children = submenu.map {
                parseMenu(
                    $0,
                    sourceElement: sourceElement,
                    targetName: targetName,
                    path: childPath
                )
            } ?? []
            let actions = actionNames(of: child)
            let enabled = boolAttribute(kAXEnabledAttribute, from: child) ?? true
            let separator = role == "AXSeparator" ||
                subrole == "AXSeparator" ||
                roleDescription?.localizedCaseInsensitiveCompare("separator") == .orderedSame ||
                (role == kAXMenuItemRole && title.isEmpty && !enabled && children.isEmpty) ||
                (title.isEmpty && children.isEmpty && !actions.contains(kAXPressAction))
            if separator {
                return ProxyMenuNode(
                    id: UUID(), kind: .separator, title: "", isEnabled: false,
                    isChecked: false, keyEquivalent: "", keyModifiers: 0,
                    actionID: nil, children: []
                )
            }
            guard role == kAXMenuItemRole || !title.isEmpty else { return nil }
            let actionID: UUID? = enabled && actions.contains(kAXPressAction) ? UUID() : nil
            if let actionID {
                actionReferences[actionID] = MenuActionReference(
                    element: child,
                    sourceElement: sourceElement,
                    path: childPath,
                    targetName: targetName
                )
            }
            let mark = stringAttribute(kAXMenuItemMarkCharAttribute, from: child) ?? ""
            return ProxyMenuNode(
                id: UUID(),
                kind: .command,
                title: title,
                isEnabled: enabled && (actionID != nil || !children.isEmpty),
                isChecked: !mark.isEmpty,
                keyEquivalent: stringAttribute(kAXMenuItemCmdCharAttribute, from: child) ?? "",
                keyModifiers: numberAttribute(kAXMenuItemCmdModifiersAttribute, from: child)?.uintValue ?? 0,
                actionID: actionID,
                children: children
            )
        }
    }

    private func element(at path: [Int], in rootMenu: AXUIElement) -> AXUIElement? {
        var menu = rootMenu
        var current: AXUIElement?
        for (offset, index) in path.enumerated() {
            let children = elementArrayAttribute(kAXChildrenAttribute, from: menu)
            guard children.indices.contains(index) else { return nil }
            current = children[index]
            if offset < path.count - 1 {
                guard let current,
                      let submenu = elementArrayAttribute(kAXChildrenAttribute, from: current).first(where: {
                          stringAttribute(kAXRoleAttribute, from: $0) == kAXMenuRole
                      }) else { return nil }
                menu = submenu
            }
        }
        return current
    }

    private func dismissOriginalMenu(
        _ menu: AXUIElement,
        sourceElement: AXUIElement,
        targetName: String
    ) async -> Bool {
        let initialVisibility = menuPresentationState(menu: menu, sourceElement: sourceElement)
        let cancelTarget: AXUIElement?
        if supportsAction(kAXCancelAction, on: menu) {
            cancelTarget = menu
        } else if supportsAction(kAXCancelAction, on: sourceElement) {
            cancelTarget = sourceElement
        } else {
            cancelTarget = nil
        }

        var dismissalResult: AXError = .actionUnsupported
        if let cancelTarget {
            dismissalResult = AXUIElementPerformAction(cancelTarget, kAXCancelAction as CFString)
        }
        interactionLogger.notice(
            "[\(targetName, privacy: .public)] AXCancel result=\(dismissalResult.rawValue, privacy: .public); initial presentation=\(String(describing: initialVisibility), privacy: .public)"
        )

        if dismissalResult != .success {
            dismissalResult = AXUIElementPerformAction(sourceElement, kAXPressAction as CFString)
            interactionLogger.notice(
                "[\(targetName, privacy: .public)] AXCancel unavailable/failed; close-toggle AXPress result=\(dismissalResult.rawValue, privacy: .public)"
            )
        }
        guard dismissalResult == .success else { return false }

        var sawPresentationSignal = initialVisibility != nil
        for _ in 0..<25 {
            if let state = menuPresentationState(menu: menu, sourceElement: sourceElement) {
                sawPresentationSignal = true
                if !state { return true }
            } else if findMenu(from: sourceElement) == nil {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }

        if sawPresentationSignal { return false }

        // Some third-party AX menus expose AXCancel but no AXVisible/AXExpanded.
        // In that case AX has no queryable completion bit. Give the successful
        // cancel two additional run-loop turns before the native proxy starts.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(40))
        await Task.yield()
        interactionLogger.notice(
            "[\(targetName, privacy: .public)] dismissal accepted from successful AX action; AX exposes no presentation-state attribute"
        )
        return true
    }

    private func menuPresentationState(
        menu: AXUIElement,
        sourceElement: AXUIElement
    ) -> Bool? {
        if let visible = boolAttribute("AXVisible", from: menu) { return visible }
        if let expanded = boolAttribute(kAXExpandedAttribute, from: sourceElement) { return expanded }
        return nil
    }

    private func logMenuEvidence(
        _ menu: AXUIElement,
        targetName: String,
        phase: String
    ) {
        interactionLogger.notice(
            "[\(targetName, privacy: .public)] AXMenu hierarchy \(phase, privacy: .public)"
        )
        logMenuChildren(menu, targetName: targetName, depth: 0)
    }

    private func logMenuChildren(
        _ menu: AXUIElement,
        targetName: String,
        depth: Int
    ) {
        for child in elementArrayAttribute(kAXChildrenAttribute, from: menu) {
            let role = stringAttribute(kAXRoleAttribute, from: child) ?? "unknown"
            let subrole = stringAttribute(kAXSubroleAttribute, from: child) ?? "none"
            let roleDescription = stringAttribute(kAXRoleDescriptionAttribute, from: child) ?? "none"
            let title = stringAttribute(kAXTitleAttribute, from: child) ?? ""
            let enabled = boolAttribute(kAXEnabledAttribute, from: child)
            let mark = stringAttribute(kAXMenuItemMarkCharAttribute, from: child) ?? ""
            let shortcut = stringAttribute(kAXMenuItemCmdCharAttribute, from: child) ?? ""
            let actions = actionNames(of: child).joined(separator: ",")
            let prefix = String(repeating: "  ", count: depth)
            interactionLogger.notice(
                "[\(targetName, privacy: .public)] \(prefix, privacy: .public)role=\(role, privacy: .public); subrole=\(subrole, privacy: .public); roleDescription=\(roleDescription, privacy: .public); title=\(title, privacy: .public); enabled=\(String(describing: enabled), privacy: .public); mark=\(mark, privacy: .public); key=\(shortcut, privacy: .public); actions=\(actions, privacy: .public)"
            )
            if let submenu = elementArrayAttribute(kAXChildrenAttribute, from: child).first(where: {
                stringAttribute(kAXRoleAttribute, from: $0) == kAXMenuRole
            }) {
                logMenuChildren(submenu, targetName: targetName, depth: depth + 1)
            }
        }
    }

    private func rebuildObservers(from targets: [(pid_t, AXUIElement, [AXUIElement])]) {
        let signature = targets.map { pid, extrasMenu, children in
            let childHashes = children.map { String(CFHash($0)) }.joined(separator: ",")
            return "\(pid):\(CFHash(extrasMenu)):\(childHashes)"
        }.sorted().joined(separator: "|")
        guard signature != observationSignature else { return }

        clearObservers()
        observationSignature = signature
        guard !targets.isEmpty else { return }
        logger.notice("starting AX observers for \(targets.count, privacy: .public) status-item processes")
        for (pid, extrasMenu, children) in targets {
            var observer: AXObserver?
            let result = AXObserverCreate(pid, { _, _, _, context in
                guard let context else { return }
                let service = Unmanaged<AccessibilityService>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in service.onMenuBarChange?() }
            }, &observer)
            guard result == .success, let observer else { continue }
            let context = Unmanaged.passUnretained(self).toOpaque()
            _ = AXObserverAddNotification(observer, extrasMenu, "AXChildrenChanged" as CFString, context)
            for child in children {
                _ = AXObserverAddNotification(observer, child, kAXMovedNotification as CFString, context)
                _ = AXObserverAddNotification(observer, child, kAXResizedNotification as CFString, context)
                _ = AXObserverAddNotification(observer, child, kAXUIElementDestroyedNotification as CFString, context)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers.append(observer)
        }
        logger.notice("stability observers installed: \(self.observers.count, privacy: .public)")
    }

    private func clearObservers() {
        let removedCount = observers.count
        for observer in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
        observationSignature = nil
        if removedCount > 0 {
            logger.notice("stability observers removed: \(removedCount, privacy: .public); remaining=0")
        }
    }

    private func isRealStatusItem(role: String?, subrole: String?) -> Bool {
        role == kAXMenuBarItemRole || subrole == "AXMenuExtra"
    }

    private func itemType(title: String, isAppleProvided: Bool) -> MenuBarItemType {
        let key = title.lowercased()
        if key.contains("controlcenter") || key.contains("control center") { return .controlCenter }
        return isAppleProvided ? .system : .application
    }

    private func isAppleProvided(_ application: NSRunningApplication) -> Bool {
        if application.bundleIdentifier?.hasPrefix("com.apple.") == true { return true }
        let roots = ["/System/", "/usr/libexec/", "/usr/sbin/"]
        let paths = [application.bundleURL?.path, application.executableURL?.path].compactMap { $0 }
        return paths.contains(where: { path in roots.contains(where: path.hasPrefix) })
    }

    private func supportsAction(_ action: String, on element: AXUIElement) -> Bool {
        actionNames(of: element).contains(action)
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success else { return [] }
        return value as? [String] ?? []
    }

    private func elementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func elementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    private func firstNonEmptyString(attributes: [String], from element: AXUIElement) -> String? {
        for attribute in attributes {
            if let string = stringAttribute(attribute, from: element) { return string }
        }
        return nil
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let number = value as? NSNumber else { return nil }
        return number.boolValue
    }

    private func numberAttribute(_ attribute: String, from element: AXUIElement) -> NSNumber? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? NSNumber
    }

    private func rectAttribute(from element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size),
              size.width > 0,
              size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func logDiagnostics(_ items: [MenuBarItem]) {
        let visible = items.filter { $0.visibilityState == .visible }.count
        let overflowed = items.filter { $0.visibilityState == .overflowed }.count
        let unknown = items.filter { $0.visibilityState == .unknown }.count
        logger.notice("detected items: \(items.count, privacy: .public); visible: \(visible, privacy: .public); overflowed: \(overflowed, privacy: .public); unknown: \(unknown, privacy: .public)")
        #if DEBUG
        for item in items {
            logger.debug("[\(item.name, privacy: .public)] frame=\(String(describing: item.accessibilityFrame), privacy: .public); result=\(item.visibilityState.rawValue, privacy: .public); reason=\(item.visibilityReason, privacy: .public)")
        }
        #endif
    }
}
