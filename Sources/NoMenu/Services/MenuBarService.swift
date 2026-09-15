import AppKit
import Combine
import CoreGraphics
import OSLog

@MainActor
final class MenuBarService: ObservableObject {
    private struct ExternalInteractionSession {
        let itemID: UUID
        let sessionID: UUID
        let targetName: String
        var window: ExternalWindowEvidence
    }

    @Published private(set) var items: [MenuBarItem] = []
    @Published private(set) var selectedItem: MenuBarItem?
    @Published private(set) var hoverHighlightEnabled: Bool
    @Published private(set) var ignoredItemIDs: Set<String>

    let accessibility: AccessibilityService
    let settings: SettingsService
    var onActivationCompleted: (() -> Void)?
    private var preferenceSubscriptions: Set<AnyCancellable> = []
    private var interactionMonitorCounts: [UUID: Int] = [:]
    private var artworkGeneration = UUID()
    private let liveCapture = LiveArtworkCapture()
    private var liveImages: [UUID: LiveArtworkImage] = [:]
    private var artworkVisible = false
    private var artworkConsumers: Set<UUID> = []
    private var artworkMappingSignature = ""
    private var artworkScreen: NSScreen?
    private var cachedPreferences: SettingsPreferences
    private let discoveryProvider: () -> AccessibilityService.DiscoveryResult
    private var interactionRecentOrder: [String] = []
    private var isPresentationOrderFrozen = false
    private static let diagnosticLogger = Logger(subsystem: "com.nomenu.utility", category: "Diagnostics")
    private var elements: [UUID: AXUIElement] = [:]
    private var icons: [UUID: NSImage] = [:]
    private var capturedIcons: [UUID: NSImage] = [:]
    private var capturedFrames: [UUID: CGRect] = [:]
    private var artworkCaptureTasks: [UUID: Task<Void, Never>] = [:]
    private var isRefreshSuspended = false
    private var hasPendingRefresh = false
    private var isDiscovering = false
    private var selectedInteractionSessionID: UUID?
    private var externalInteractionSession: ExternalInteractionSession?
    private var externalInteractionMonitorTask: Task<Void, Never>?

    init(
        accessibility: AccessibilityService,
        settings: SettingsService,
        ignoredItemIDs: Set<String> = [],
        hoverHighlightEnabled: Bool = true,
        discoveryProvider: (() -> AccessibilityService.DiscoveryResult)? = nil
    ) {
        self.accessibility = accessibility
        self.settings = settings
        self.cachedPreferences = settings.preferences
        self.discoveryProvider = discoveryProvider ?? { accessibility.discoverMenuBarItems() }
        self.ignoredItemIDs = ignoredItemIDs
        self.hoverHighlightEnabled = hoverHighlightEnabled
        settings.$preferences.dropFirst().sink { [weak self] value in
            guard let self else { return }
            self.cachedPreferences = value
            self.updateLiveArtwork()
            self.objectWillChange.send()
        }.store(in: &preferenceSubscriptions)
        settings.$hoverHighlightEnabled.sink { [weak self] in self?.setHoverHighlightEnabled($0) }
            .store(in: &preferenceSubscriptions)
        settings.$ignoredItemIDs.sink { [weak self] in self?.setIgnoredItemIDs($0) }
            .store(in: &preferenceSubscriptions)
        settings.$screenRecordingAuthorized.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateLiveArtwork() }
        }.store(in: &preferenceSubscriptions)
        liveCapture.onFrames = { [weak self] frames in
            guard let self, self.artworkVisible else { return }
            for (id, frame) in frames where self.artworkConsumers.contains(id) {
                self.liveArtwork(for: id).accept(frame)
            }
        }
        liveCapture.onFailure = { [weak settings] in settings?.refreshScreenRecordingStatus() }
        liveCapture.permissionIsGranted = { [weak settings] in
            settings?.screenRecordingAuthorized == true
        }
    }

    var overflowItems: [MenuBarItem] {
        items
            .filter {
                $0.visibilityState == .overflowed
                    && !ignoredItemIDs.contains($0.stableIdentity)
            }
            .sorted { lhs, rhs in
                switch cachedPreferences.itemOrder {
                case .alphabetical:
                    let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    if order != .orderedSame { return order == .orderedAscending }
                case .recent:
                    // A visible NoMenu panel is one continuous interaction
                    // surface. Do not let recording an activation reorder the
                    // physical buttons underneath the pointer after the active
                    // item closes. Apply the updated recent order only after
                    // the panel presentation ends.
                    let recentOrder = isPresentationOrderFrozen || selectedItem != nil
                        ? interactionRecentOrder
                        : cachedPreferences.recentlyUsed
                    let left = recentOrder.firstIndex(of: lhs.stableIdentity) ?? Int.max
                    let right = recentOrder.firstIndex(of: rhs.stableIdentity) ?? Int.max
                    if left != right { return left < right }
                case .menuBar: break
                }
                switch (lhs.accessibilityFrame, rhs.accessibilityFrame) {
                case let (left?, right?) where abs(left.minX - right.minX) > 0.5:
                    return left.minX < right.minX
                default:
                    return lhs.discoveryOrder < rhs.discoveryOrder
                }
            }
    }

    var diagnosticsSummary: String {
        let visible = items.filter { $0.visibilityState == .visible }.count
        let overflowed = items.filter { $0.visibilityState == .overflowed }.count
        let unknown = items.filter { $0.visibilityState == .unknown }.count
        return "Detected: \(items.count) · Visible: \(visible) · Overflowed: \(overflowed) · Unknown: \(unknown)"
    }

    var ignoredItems: [MenuBarItem] {
        items.filter { ignoredItemIDs.contains($0.stableIdentity) }
    }

    func icon(for item: MenuBarItem) -> NSImage? {
        switch cachedPreferences.iconAppearance {
        case .automatic: return liveImages[item.id]?.image ?? icons[item.id]
        case .captured: return liveImages[item.id]?.image ?? capturedIcons[item.id] ?? icons[item.id]
        case .appIcon: return NSRunningApplication(processIdentifier: item.processIdentifier)?.icon
        }
    }

    var discoveryState: String {
        if !accessibility.isTrusted { return "Waiting for Accessibility" }
        return isRefreshSuspended ? "Suspended for presentation" : "Ready"
    }

    func liveArtwork(for id: UUID) -> LiveArtworkImage {
        if let image = liveImages[id] { return image }
        let image = LiveArtworkImage()
        liveImages[id] = image
        return image
    }

    func setArtworkVisibility(_ visible: Bool, screen: NSScreen?) {
        if artworkVisible != visible {
            Self.diagnosticLogger.notice("Artwork UI visible=\(visible); displayed=\(visible ? self.overflowItems.count : 0)")
        }
        artworkVisible = visible
        artworkScreen = screen
        updateLiveArtwork()
    }

    private func updateLiveArtwork() {
        let displayed = artworkVisible ? overflowItems : []
        artworkConsumers = cachedPreferences.iconAppearance == .appIcon ? [] : Set(displayed.map(\.id))
        if artworkVisible { settings.refreshScreenRecordingStatus() }
        guard artworkVisible, !NSApp.isHidden,
              cachedPreferences.iconAppearance != .appIcon,
              settings.screenRecordingAuthorized,
              let screen = artworkScreen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            liveCapture.update(nil)
            return
        }
        let display = number.uint32Value
        let bounds = CGDisplayBounds(display)
        let height = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let strip = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let frames = ArtworkSourceMapping.sources(for: displayed, strip: strip, screen: screen, windows: windows)
        let signature = displayed.map { "\($0.id):\($0.visibilityState):\(String(describing: $0.accessibilityFrame)):\(String(describing: frames[$0.id]))" }.sorted().joined(separator: "|")
        if signature != artworkMappingSignature {
            artworkMappingSignature = signature
            Self.diagnosticLogger.notice("Artwork mapping: displayed=\(displayed.count) subscribers=\(self.artworkConsumers.count) cropRegions=\(frames.count)")
            for item in items where item.applicationName.localizedCaseInsensitiveContains("runcat") {
                let source = frames[item.id]
                let sourceType = source != nil
                    ? "LIVE_CAPTURE"
                    : (capturedIcons[item.id] != nil ? "STATIC_CAPTURE"
                        : (icons[item.id] != nil ? "APP_ICON_FALLBACK" : "UNAVAILABLE"))
                Self.diagnosticLogger.notice("[NoMenuLiveArtwork] itemID=\(item.id.uuidString, privacy: .public) stableIdentity=\(item.stableIdentity, privacy: .public) bundleID=\(item.bundleIdentifier ?? "unknown", privacy: .public) PID=\(item.processIdentifier) AXFrame=\(String(describing: item.accessibilityFrame), privacy: .public) captureTarget=\(String(describing: source), privacy: .public) displayID=\(display) strip=\(String(describing: strip), privacy: .public) screenRecording=\(self.settings.screenRecordingAuthorized) requestedFPS=\(self.cachedPreferences.liveArtworkFrameRate.framesPerSecond) sourceType=\(sourceType, privacy: .public) classification=\(item.visibilityState.rawValue, privacy: .public) displayed=\(displayed.contains(where: { $0.id == item.id })) consumers=\(self.artworkConsumers.count) lastCapture=\(String(describing: self.liveImages[item.id]?.lastCaptureTimestamp), privacy: .public)")
            }
        }
        liveCapture.update(frames.isEmpty ? nil : .init(
            displayID: display,
            strip: strip,
            frames: frames,
            fps: cachedPreferences.liveArtworkFrameRate
        ))
    }

    var activeInteractionMonitorCount: Int {
        interactionMonitorCounts.values.reduce(0, +)
    }
    var isExternalInteractionPolling: Bool { externalInteractionMonitorTask != nil }
    func reportInteractionMonitors(owner: UUID, count: Int) {
        if count == 0 { interactionMonitorCounts.removeValue(forKey: owner) }
        else { interactionMonitorCounts[owner] = count }
    }
    func refreshFromSettings() {
        let wasTrusted = accessibility.isTrusted
        guard accessibility.refreshAccessibilityState(reason: "Settings discovery refresh") else { return }
        // The app's transition callback already starts discovery on false -> true.
        guard wasTrusted || accessibility.onTrustChange == nil else { return }
        refresh()
    }
    func restartDiscovery() {
        cancelInteraction()
        accessibility.stopAccessibilityServices()
        refreshFromSettings()
    }
    func clearArtworkCache(refreshAfterward: Bool = true) {
        for image in liveImages.values { image.clear() }
        artworkGeneration = UUID()
        for task in artworkCaptureTasks.values { task.cancel() }
        artworkCaptureTasks.removeAll()
        capturedIcons.removeAll()
        capturedFrames.removeAll()
        icons.removeAll()
        accessibility.clearArtworkCache()
        objectWillChange.send()
        if refreshAfterward { refreshFromSettings() }
    }
    func activationCompleted(for item: MenuBarItem) {
        settings.recordUse(of: item)
        if settings.preferences.keepOpenAfterActivation { onActivationCompleted?() }
    }

    func setHoverHighlightEnabled(_ enabled: Bool) {
        if hoverHighlightEnabled != enabled {
            hoverHighlightEnabled = enabled
        }
    }

    func setIgnoredItemIDs(_ identities: Set<String>) {
        guard ignoredItemIDs != identities else { return }
        ignoredItemIDs = identities
        updateLiveArtwork()
        if let selectedItem, identities.contains(selectedItem.stableIdentity) {
            closeExternalInteractionIfNeeded(reason: "selected item became ignored")
            self.selectedItem = nil
            selectedInteractionSessionID = nil
        }
    }

    func refresh(force: Bool = false) {
        // A fresh trust check inside discovery may synchronously invoke the
        // permission-transition callback. Let this pass own that discovery.
        guard !isDiscovering else { return }
        guard force || !isRefreshSuspended else {
            hasPendingRefresh = true
            return
        }
        hasPendingRefresh = false
        isDiscovering = true
        defer { isDiscovering = false }
        let result = discoveryProvider()
        elements = result.elements
        icons = result.icons.merging(capturedIcons) { _, captured in captured }
        if items != result.items { items = result.items }
        if let selectedItem, !overflowItems.contains(where: { $0.id == selectedItem.id }) {
            closeExternalInteractionIfNeeded(reason: "selected item left overflow set")
            self.selectedItem = nil
            selectedInteractionSessionID = nil
        }
        captureVisibleArtworkIfAvailable()
        if settings.preferences.diagnosticLogging {
            Self.diagnosticLogger.notice("Discovery finished: detected=\(self.items.count) overflowed=\(self.overflowItems.count) observers=\(self.accessibility.observerCount)")
        }
    }

    func setRefreshSuspended(_ suspended: Bool) {
        guard isRefreshSuspended != suspended else { return }
        isRefreshSuspended = suspended
        if !suspended && hasPendingRefresh { refresh() }
    }

    func setPresentationOrderFrozen(_ frozen: Bool) {
        guard isPresentationOrderFrozen != frozen else { return }
        if frozen {
            interactionRecentOrder = cachedPreferences.recentlyUsed
        }
        isPresentationOrderFrozen = frozen
        Self.diagnosticLogger.notice(
            "[NoMenuRoutingOwnership] stage=presentation-order frozen=\(frozen, privacy: .public) snapshotCount=\(self.interactionRecentOrder.count, privacy: .public)"
        )
        objectWillChange.send()
    }

    func accessibilityDidBecomeUnavailable() {
        liveCapture.update(nil)
        hasPendingRefresh = false
        closeExternalInteractionIfNeeded(reason: "Accessibility became unavailable")
        selectedItem = nil
        selectedInteractionSessionID = nil
        elements.removeAll()
        icons.removeAll()
        for task in artworkCaptureTasks.values { task.cancel() }
        artworkCaptureTasks.removeAll()
        if !items.isEmpty { items = [] }
    }

    @discardableResult
    func beginInteraction(for item: MenuBarItem) -> UUID {
        if selectedItem == nil && !isPresentationOrderFrozen {
            interactionRecentOrder = cachedPreferences.recentlyUsed
        }
        closeExternalInteractionIfNeeded(reason: "switching items")
        let sessionID = UUID()
        selectedInteractionSessionID = sessionID
        selectedItem = item
        return sessionID
    }

    /// Completes the toggle-off half of an item interaction synchronously.
    /// Proxy menu tracking and external popover ownership must never outlive the
    /// selected/highlighted state after the same active item is clicked.
    @discardableResult
    func toggleOffInteractionIfActive(for item: MenuBarItem) -> Bool {
        guard selectedItem?.id == item.id else { return false }
        cancelInteraction()
        return true
    }

    func interaction(
        for item: MenuBarItem,
        routingEventID: UUID? = nil,
        sessionID: UUID? = nil
    ) async -> ItemInteraction {
        guard let element = elements[item.id] else {
            Self.diagnosticLogger.error(
                "[NoMenuRoutingOwnership] eventID=\(routingEventID?.uuidString ?? "none", privacy: .public) stage=ax-target-missing proxySessionID=\(sessionID?.uuidString ?? "none", privacy: .public) expectedTarget=\(item.stableIdentity, privacy: .public) itemID=\(item.id.uuidString, privacy: .public)"
            )
            return ItemInteraction(kind: .unsupported, menu: [])
        }
        var actualPID: pid_t = 0
        let pidResult = AXUIElementGetPid(element, &actualPID)
        Self.diagnosticLogger.notice(
            "[NoMenuRoutingOwnership] eventID=\(routingEventID?.uuidString ?? "none", privacy: .public) stage=ax-target-resolved proxySessionID=\(sessionID?.uuidString ?? "none", privacy: .public) actionTargetItem=\(item.stableIdentity, privacy: .public) AXTargetItem=\(item.stableIdentity, privacy: .public) expectedPID=\(item.processIdentifier, privacy: .public) actualPID=\(actualPID, privacy: .public) pidLookupResult=\(pidResult.rawValue, privacy: .public) expectedTarget=\(item.stableIdentity, privacy: .public)"
        )
        return await accessibility.interaction(
            for: element,
            targetName: item.name,
            targetPID: item.processIdentifier,
            bundleIdentifier: item.bundleIdentifier
        )
    }

    func retainExternalInteraction(
        for item: MenuBarItem,
        sessionID: UUID,
        window: ExternalWindowEvidence
    ) {
        guard isInteractionCurrent(for: item.id, sessionID: sessionID) else {
            if let element = elements[item.id] {
                _ = accessibility.dismissExternalInteraction(
                    for: element,
                    evidence: window,
                    targetName: item.name
                )
            }
            return
        }

        externalInteractionMonitorTask?.cancel()
        externalInteractionSession = ExternalInteractionSession(
            itemID: item.id,
            sessionID: sessionID,
            targetName: item.name,
            window: window
        )
        externalInteractionMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var consecutiveMisses = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled,
                      var session = externalInteractionSession,
                      session.itemID == item.id,
                      session.sessionID == sessionID else { return }
                if let current = accessibility.currentExternalWindow(matching: session.window) {
                    consecutiveMisses = 0
                    session.window = current
                    externalInteractionSession = session
                } else {
                    consecutiveMisses += 1
                    if consecutiveMisses >= 2 {
                        externalInteractionSession = nil
                        externalInteractionMonitorTask = nil
                        endInteraction(for: item.id, sessionID: sessionID)
                        return
                    }
                }
            }
        }
    }

    func shouldPreserveExternalInteraction(at screenPoint: NSPoint) -> Bool {
        guard var session = externalInteractionSession,
              let current = accessibility.currentExternalWindow(matching: session.window) else {
            return false
        }
        session.window = current
        externalInteractionSession = session
        return current.appKitBounds.insetBy(dx: -3, dy: -3).contains(screenPoint)
    }

    func isInteractionCurrent(for itemID: UUID, sessionID: UUID) -> Bool {
        selectedItem?.id == itemID && selectedInteractionSessionID == sessionID
    }

    func endInteraction(for itemID: UUID, sessionID: UUID) {
        guard selectedItem?.id == itemID,
              selectedInteractionSessionID == sessionID else { return }
        if externalInteractionSession?.itemID == itemID,
           externalInteractionSession?.sessionID == sessionID {
            externalInteractionMonitorTask?.cancel()
            externalInteractionMonitorTask = nil
            externalInteractionSession = nil
        }
        selectedItem = nil
        selectedInteractionSessionID = nil
    }

    func cancelInteraction() {
        closeExternalInteractionIfNeeded(reason: "interaction cancelled")
        selectedItem = nil
        selectedInteractionSessionID = nil
    }

    func performMenuAction(_ actionID: UUID) {
        let activatedItem = selectedItem
        Task { @MainActor [weak self] in
            guard let self else { return }
            let succeeded = await accessibility.performMenuAction(actionID)
            if succeeded, let activatedItem { activationCompleted(for: activatedItem) }
            try? await Task.sleep(for: .milliseconds(120))
            refresh()
        }
    }

    func openApplication(for item: MenuBarItem) {
        closeExternalInteractionIfNeeded(reason: "opening application")
        selectedItem = nil
        selectedInteractionSessionID = nil
        NSRunningApplication(processIdentifier: item.processIdentifier)?
            .activate(options: [.activateAllWindows])
    }

    private func closeExternalInteractionIfNeeded(reason: String) {
        externalInteractionMonitorTask?.cancel()
        externalInteractionMonitorTask = nil
        guard let session = externalInteractionSession else { return }
        externalInteractionSession = nil
        guard let element = elements[session.itemID] else { return }
        _ = accessibility.dismissExternalInteraction(
            for: element,
            evidence: session.window,
            targetName: "\(session.targetName) [\(reason)]"
        )
    }

    private func captureVisibleArtworkIfAvailable() {
        updateLiveArtwork()
    }
}
