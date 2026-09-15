import AppKit
import OSLog
import SwiftUI
import Combine

enum NoMenuPresentationState: Equatable {
    case closed
    case opening
    case open
    case closing

    var isActive: Bool { self != .closed }
    var isTransitioning: Bool { self == .opening || self == .closing }
}

/// One global mouse-down can have exactly one owner.  The panel's own controls
/// receive local AppKit/SwiftUI delivery; this classifier covers the regions a
/// global monitor can observe without guessing from nearby icon geometry.
enum NoMenuGlobalMouseDownClassification: Equatable {
    case statusItem
    case panel
    case externalInteraction
    case outside

    static func classify(
        point: NSPoint,
        statusItemFrame: NSRect,
        panelFrame: NSRect,
        preservesExternalInteraction: Bool
    ) -> Self {
        if statusItemFrame.contains(point) { return .statusItem }
        if panelFrame.contains(point) { return .panel }
        if preservesExternalInteraction { return .externalInteraction }
        return .outside
    }
}

struct NoMenuSpacePresentationContext: Equatable {
    private(set) var activeGeneration = 0
    private(set) var presentedGeneration: Int?

    mutating func activeSpaceDidChange() {
        activeGeneration &+= 1
        presentedGeneration = nil
    }

    mutating func markPresented() {
        presentedGeneration = activeGeneration
    }

    mutating func clearPresentation() {
        presentedGeneration = nil
    }

    func presentationIsStale(panelVisible: Bool, sameScreen: Bool) -> Bool {
        presentedGeneration != activeGeneration || !panelVisible || !sameScreen
    }
}

@MainActor
final class NoMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            MenuBarClickDiagnostics.record("panel-sendEvent", event: event, consumed: false)
        }
        super.sendEvent(event)
    }
}

@MainActor
final class PanelController {
    private struct AppearanceSignature: Equatable {
        let background: NoMenuBackgroundStyle
        let transparency: Double
        let blur: NoMenuBackgroundBlur
        let position: NoMenuBarPosition
        let margin: NoMenuScreenEdgeMargin
        let size: NoMenuBarSize
        let width: NoMenuBarWidth
        let spacing: IconSpacing

        init(_ preferences: SettingsPreferences) {
            background = preferences.barBackgroundStyle
            transparency = preferences.barTransparency
            blur = preferences.barBackgroundBlur
            position = preferences.barPosition
            margin = preferences.barEdgeMargin
            size = preferences.barSize
            width = preferences.barWidth
            spacing = preferences.iconSpacing
        }
    }
    private var artworkNotifications: Set<AnyCancellable> = []
    private var artworkSleeping = false
    private let panel: NoMenuPanel
    private let service: MenuBarService
    private let statusButtonProvider: () -> NSStatusBarButton?
    private let interactionLogger = Logger(subsystem: "com.nomenu.utility", category: "Interaction")
    private let spaceLogger = Logger(subsystem: "com.nomenu.utility", category: "Space")
    private let displayLogger = Logger(subsystem: "com.nomenu.utility", category: "Display")
    private let onPresentationStateChange: (NoMenuPresentationState) -> Void
    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var restingFrame = NSRect.zero
    private var statusButtonScreenFrame = NSRect.zero
    private var targetScreen: NSScreen?
    private var pendingLayoutRefresh = false
    private var pendingDisplayRegressionRefresh = false
    private var spaceContext = NoMenuSpacePresentationContext()
    private var transitionGeneration = 0
    var activePanelCount: Int { panel.isVisible ? 1 : 0 }
    var activeEventMonitorCount: Int { (globalMouseMonitor == nil ? 0 : 1) + (localKeyMonitor == nil ? 0 : 1) }
    var clickDiagnosticState: String {
        "presentation=\(presentationState) selectedItem=\(service.selectedItem?.id.uuidString ?? "none") outsideMonitor=\(globalMouseMonitor != nil) keyMonitor=\(localKeyMonitor != nil) cachedStatusFrame=\(statusButtonScreenFrame)"
    }
    private(set) var presentationState: NoMenuPresentationState = .closed {
        didSet {
            guard oldValue != presentationState else { return }
            refreshArtworkVisibility()
            onPresentationStateChange(presentationState)
        }
    }

    init(
        service: MenuBarService,
        accessibility: AccessibilityService,
        statusButtonProvider: @escaping () -> NSStatusBarButton? = { nil },
        onPresentationStateChange: @escaping (NoMenuPresentationState) -> Void
    ) {
        self.service = service
        self.statusButtonProvider = statusButtonProvider
        self.onPresentationStateChange = onPresentationStateChange
        panel = NoMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 36),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        // A status-item utility must be orderable on every Space without activating
        // the app. `canJoinAllSpaces` is therefore intentional. `moveToActiveSpace`
        // is not combined with it: those are competing placement models, and this
        // retained nonactivating panel is explicitly reset on a Space transition and
        // ordered using the current status-button screen on the next click.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // NoMenu coordinates its own reveal animation. Disabling the implicit panel
        // animation prevents a second AppKit animation from racing it.
        panel.animationBehavior = .none

        panel.contentViewController = NSHostingController(
            rootView: MenuBarPanel(
                service: service,
                accessibility: accessibility
            )
        )
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didChangeScreenNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshTargetScreen()
                    self?.refreshArtworkVisibility()
                }
            }.store(in: &artworkNotifications)
        }
        for (name, sleeping) in [(NSWorkspace.screensDidSleepNotification, true),
                                 (NSWorkspace.screensDidWakeNotification, false),
                                 (NSWorkspace.sessionDidResignActiveNotification, true),
                                 (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.artworkSleeping = sleeping
                    self?.refreshArtworkVisibility()
                }
            }.store(in: &artworkNotifications)
        }
        service.settings.$preferences
            .map(AppearanceSignature.init)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.appearanceDidChange() }
            }
            .store(in: &artworkNotifications)
    }

    private func appearanceDidChange() {
        guard !presentationState.isTransitioning else {
            pendingLayoutRefresh = true
            return
        }
        let target = frameForPanel(relativeTo: nil)
        restingFrame = target
        if panel.frame == target {
            refreshWallpaperIfNeeded(panelFrame: target)
            panel.contentView?.needsDisplay = true
            return
        }
        if presentationState == .open, panel.isVisible, panel.frame != target {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = service.settings.animationsAllowed ? 0.25 : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshWallpaperIfNeeded(panelFrame: target)
                    self.panel.contentView?.layoutSubtreeIfNeeded()
                }
            }
        } else {
            panel.setFrame(target, display: panel.isVisible, animate: false)
            refreshWallpaperIfNeeded(panelFrame: target)
            panel.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func refreshArtworkVisibility() {
        service.setArtworkVisibility(!artworkSleeping && presentationState == .open && panel.isVisible
                                     && panel.occlusionState.contains(.visible), screen: panel.screen)
    }

    func prepare(relativeTo statusButton: NSStatusBarButton?) {
        guard presentationState == .closed else { return }
        statusButtonScreenFrame = screenFrame(of: statusButton) ?? .zero
        restingFrame = frameForPanel(relativeTo: statusButton)
        refreshWallpaperIfNeeded()
        panel.setFrame(restingFrame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
    }

    func toggle(relativeTo statusButton: NSStatusBarButton?) {
        let clickScreen = screenForStatusButton(statusButton)
        logSpaceSnapshot(reason: "status item clicked", clickScreen: clickScreen)

        // Defensive reconciliation for a delayed Space notification or a window
        // server state where AppKit still says the old panel is visible. Never let
        // an old-Space `.open` state turn the current Space's first click into hide.
        if presentationState == .open,
           spaceContext.presentationIsStale(
               panelVisible: panel.isVisible,
               sameScreen: clickScreen == nil || panel.screen === clickScreen
           ) {
            resetTransientPresentation(reason: "stale presentation found at click")
        }

        switch presentationState {
        case .closed:
            show(relativeTo: statusButton)
        case .open:
            hide()
        case .opening, .closing:
            MenuBarClickDiagnostics.record("status-toggle-ignored-during-transition", event: NSApp.currentEvent)
            // Do not restart an in-flight transition. A new transition begins only
            // after the panel reaches a stable presentation state.
            break
        }
    }

    func show(relativeTo statusButton: NSStatusBarButton?) {
        guard presentationState == .closed else { return }
        transitionGeneration &+= 1
        let generation = transitionGeneration
        service.setPresentationOrderFrozen(true)
        service.setRefreshSuspended(true)
        statusButtonScreenFrame = screenFrame(of: statusButton) ?? .zero
        let targetFrame = frameForPanel(relativeTo: statusButton)
        if restingFrame != targetFrame || panel.frame != restingFrame {
            restingFrame = targetFrame
            panel.setFrame(restingFrame, display: false)
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.contentView?.displayIfNeeded()
        }
        let hiddenOrigin = NSPoint(x: restingFrame.origin.x, y: restingFrame.origin.y + 10)

        // Normal presentations use the already-prepared frame and hosting layout.
        // Only the window origin and alpha animate; its size and SwiftUI hierarchy
        // remain stable for the entire transition.
        panel.setFrameOrigin(hiddenOrigin)
        panel.alphaValue = 0
        installEventMonitors()
        spaceContext.markPresented()
        presentationState = .opening
        panel.orderFrontRegardless()
        logSpaceSnapshot(reason: "panel ordered on current Space", clickScreen: targetScreen)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = service.settings.animationsAllowed ? 0.18 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(restingFrame.origin)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transitionGeneration == generation,
                      self.presentationState == .opening else { return }
                self.panel.alphaValue = 1
                self.presentationState = .open
                self.service.setRefreshSuspended(false)
                self.applyPendingLayoutRefreshIfNeeded()
            }
        })
    }

    func hide() {
        // The outside monitor is installed before orderFront so the first click
        // after opening is still meaningful.  Treat an outside click during the
        // short reveal as a normal dismissal instead of silently requiring a
        // second click after the panel reaches `.open`.
        guard presentationState == .open || presentationState == .opening else { return }
        transitionGeneration &+= 1
        let generation = transitionGeneration
        service.setRefreshSuspended(true)
        presentationState = .closing
        if service.selectedItem != nil {
            service.cancelInteraction()
        }
        let hiddenOrigin = NSPoint(x: restingFrame.origin.x, y: restingFrame.origin.y + 10)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = service.settings.animationsAllowed ? 0.18 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(hiddenOrigin)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transitionGeneration == generation,
                      self.presentationState == .closing else { return }
                self.panel.orderOut(nil)
                self.panel.setFrameOrigin(self.restingFrame.origin)
                self.panel.alphaValue = 1
                self.presentationState = .closed
                self.spaceContext.clearPresentation()
                self.service.setPresentationOrderFrozen(false)
                self.service.setRefreshSuspended(false)
                self.removeEventMonitors()
                self.applyPendingLayoutRefreshIfNeeded()
            }
        })
    }

    func activeSpaceDidChange() {
        spaceContext.activeSpaceDidChange()
        logSpaceSnapshot(reason: "Space changed; invalidating stale presentation state",
                         clickScreen: nil)
        resetTransientPresentation(reason: "active Space changed")
    }

    func screenParametersDidChange() {
        displayLogger.notice(
            "[NoMenuDisplayRegression] displayChange received BEFORE \(self.displayRegressionSnapshot(), privacy: .public)"
        )
        pendingDisplayRegressionRefresh = true
        MenuBarClickDiagnostics.markDisplayGeometryInvalidated()
        WallpaperTintProvider.shared.invalidateScreenCache()

        // A retained NSScreen, absolute panel origin, status-item frame and any
        // active proxy all belong to the old display coordinate system. Retire
        // them as one transaction; the app remains running and the next prepare
        // resolves only from the replacement NSScreen configuration.
        resetTransientPresentation(reason: "screen parameters changed")
        prepare(relativeTo: statusButtonProvider())
        displayLogger.notice(
            "[NoMenuDisplayRegression] displayChange invalidated AFTER \(self.displayRegressionSnapshot(), privacy: .public)"
        )
    }

    func displayConfigurationRefreshCompleted() {
        guard pendingDisplayRegressionRefresh else { return }
        pendingDisplayRegressionRefresh = false
        displayLogger.notice(
            "[NoMenuDisplayRegression] settled discovery AFTER \(self.displayRegressionSnapshot(), privacy: .public)"
        )
    }

    func keepOpenAfterActivation() {
        // Keep a still-open MoreUI above an app that activated itself. Never
        // resurrect a panel dismissed by an outside click while an AX action awaited.
        guard presentationState == .open else { return }
        panel.orderFrontRegardless()
    }

    private func frameForPanel(relativeTo statusButton: NSStatusBarButton?) -> NSRect {
        let screen = screenForStatusButton(statusButton)
            ?? targetScreen ?? panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        targetScreen = screen
        return NoMenuBarLayout.resolve(
            screen: screen,
            itemCount: service.overflowItems.count,
            preferences: service.settings.preferences
        ).frame
    }

    private func refreshTargetScreen() {
        if let screen = panel.screen { targetScreen = screen }
        // NSWindow can report its new screen while a frame animation/configuration
        // transaction is still in flight. Keep the last valid wallpaper until the
        // authoritative resting frame is installed; the completion path refreshes it.
        guard panel.frame == restingFrame else { return }
        refreshWallpaperIfNeeded()
    }

    private func refreshWallpaperIfNeeded(panelFrame: NSRect? = nil) {
        guard service.settings.preferences.barBackgroundStyle == .wallpaper else { return }
        WallpaperTintProvider.shared.refresh(
            for: targetScreen ?? panel.screen ?? NSScreen.main ?? NSScreen.screens[0],
            panelFrame: panelFrame ?? restingFrame
        )
    }

    private func applyPendingLayoutRefreshIfNeeded() {
        guard pendingLayoutRefresh else { return }
        pendingLayoutRefresh = false
        appearanceDidChange()
    }

    private func screenFrame(of button: NSStatusBarButton?) -> NSRect? {
        guard let button, let window = button.window else { return nil }
        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    private func screenForStatusButton(_ button: NSStatusBarButton?) -> NSScreen? {
        if let screen = button?.window?.screen { return screen }
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    private func resetTransientPresentation(reason: String) {
        transitionGeneration &+= 1
        pendingLayoutRefresh = false
        service.cancelInteraction()
        service.setPresentationOrderFrozen(false)
        service.setRefreshSuspended(false)
        service.setArtworkVisibility(false, screen: nil)
        removeEventMonitors()
        panel.orderOut(nil)
        panel.alphaValue = 1
        presentationState = .closed
        spaceContext.clearPresentation()
        restingFrame = .zero
        statusButtonScreenFrame = .zero
        targetScreen = nil
        spaceLogger.notice("[NoMenu Space Debug] transient presentation reset; reason=\(reason, privacy: .public); generation=\(self.spaceContext.activeGeneration, privacy: .public)")
    }

    private func logSpaceSnapshot(reason: String, clickScreen: NSScreen?) {
        let mouse = NSEvent.mouseLocation
        let clicked = screenDescription(clickScreen)
        let panelScreen = screenDescription(panel.screen)
        spaceLogger.notice("[NoMenu Space Debug] \(reason, privacy: .public); generation=\(self.spaceContext.activeGeneration, privacy: .public); presentation=\(String(describing: self.presentationState), privacy: .public); visible=\(self.panel.isVisible, privacy: .public); occlusion=\(self.panel.occlusionState.rawValue, privacy: .public); panelScreen=\(panelScreen, privacy: .public); clickScreen=\(clicked, privacy: .public); mouse=\(String(describing: mouse), privacy: .public); frame=\(String(describing: self.panel.frame), privacy: .public); collection=\(self.panel.collectionBehavior.rawValue, privacy: .public); selected=\(self.service.selectedItem != nil, privacy: .public); outsideMonitor=\(self.globalMouseMonitor != nil, privacy: .public); keyMonitor=\(self.localKeyMonitor != nil, privacy: .public)")

        for window in NSApp.windows {
            let parent = window.parent?.windowNumber ?? 0
            let children = window.childWindows?.map(\.windowNumber) ?? []
            spaceLogger.debug("[NoMenu Space Debug] window=\(window.windowNumber, privacy: .public); class=\(String(describing: type(of: window)), privacy: .public); frame=\(String(describing: window.frame), privacy: .public); screen=\(self.screenDescription(window.screen), privacy: .public); visible=\(window.isVisible, privacy: .public); key=\(window.isKeyWindow, privacy: .public); main=\(window.isMainWindow, privacy: .public); level=\(window.level.rawValue, privacy: .public); collection=\(window.collectionBehavior.rawValue, privacy: .public); alpha=\(window.alphaValue, privacy: .public); ignoresMouse=\(window.ignoresMouseEvents, privacy: .public); parent=\(parent, privacy: .public); children=\(String(describing: children), privacy: .public)")
        }
    }

    private func screenDescription(_ screen: NSScreen?) -> String {
        guard let screen else { return "none" }
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            .map(String.init(describing:)) ?? "unknown"
        return "\(screen.localizedName)#\(number) frame=\(screen.frame)"
    }

    private func displayRegressionSnapshot() -> String {
        let statusButton = statusButtonProvider()
        let currentStatusFrame = screenFrame(of: statusButton) ?? .zero
        let buttons = descendantViews(of: panel.contentView).compactMap { $0 as? OverflowItemNSButton }
        let hitFrames = buttons.map { button -> String in
            let frame: NSRect
            if let window = button.window {
                frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            } else {
                frame = .zero
            }
            return "\(button.representedItem?.id.uuidString ?? "none")@\(frame)"
        }.joined(separator: ",")
        let proxyOwners = Set(buttons.compactMap {
            ($0.target as? MenuItemButton.Coordinator)?.displayRegressionProxyOwnerDescription
        }).sorted().joined(separator: ",")
        return "targetScreen={\(screenDescription(targetScreen))}; panelScreen={\(screenDescription(panel.screen))}; panelFrame=\(panel.frame); restingFrame=\(restingFrame); statusFrameCurrent=\(currentStatusFrame); statusFrameCached=\(statusButtonScreenFrame); itemHitFrames=[\(hitFrames)]; activeItem=\(service.selectedItem?.id.uuidString ?? "none"); proxyOwners=[\(proxyOwners)]"
    }

    private func descendantViews(of root: NSView?) -> [NSView] {
        guard let root else { return [] }
        return [root] + root.subviews.flatMap { descendantViews(of: $0) }
    }

    private func installEventMonitors() {
        removeEventMonitors()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                MenuBarClickDiagnostics.record("outside-monitor-received", event: event, consumed: false)
            }
            Task { @MainActor in
                guard let self else { return }
                // Do not reread NSEvent.mouseLocation here.  It may have moved
                // between the physical mouse-down and this asynchronous monitor
                // callback, which previously made an outside click look like a
                // nearby icon/item click.
                let pointer = self.screenPoint(for: event)
                MenuBarClickDiagnostics.record("outside-monitor-handling", point: pointer, consumed: false)
                let currentStatusFrame = self.screenFrame(of: self.statusButtonProvider())
                    ?? self.statusButtonScreenFrame
                let classification = NoMenuGlobalMouseDownClassification.classify(
                    point: pointer,
                    statusItemFrame: currentStatusFrame,
                    panelFrame: self.panel.frame,
                    preservesExternalInteraction: self.service.shouldPreserveExternalInteraction(at: pointer)
                )
                switch classification {
                case .statusItem, .panel:
                    return
                case .externalInteraction:
                    // A verified app-owned popover is part of the active interaction,
                    // even though it lives outside NoMenu's process and panel frame.
                    self.interactionLogger.notice(
                        "outside dismissal suppressed for verified external interaction at \(String(describing: pointer), privacy: .public)"
                    )
                    return
                case .outside:
                    self.interactionLogger.debug(
                        "ordinary outside dismissal at \(String(describing: pointer), privacy: .public)"
                    )
                    self.hide()
                }
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53,
               self?.service.settings.preferences.closeWithEscape == true,
               event.window === self?.panel {
                Task { @MainActor in self?.hide() }
                return nil
            }
            return event
        }
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        guard let window = event.window else {
            // Global monitors deliver a nil window and locationInWindow is then
            // expressed in the global AppKit screen coordinate space.
            return event.locationInWindow
        }
        return window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
    }

    private func removeEventMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}
