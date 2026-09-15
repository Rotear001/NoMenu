import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private struct NativeTitlebarGeometry {
        let titlebarView: NSView
        let titlebarViewFrame: NSRect
        let titlebarContainer: NSView
        let titlebarContainerFrame: NSRect
        let buttonFrames: [NSRect]
    }

    private let settings: SettingsService
    private var preferenceObservations: Set<AnyCancellable> = []
    private weak var sidebarMaterial: SettingsSidebarMaterialView?
    private weak var hostingView: NSView?
    private var trafficLightButtons: [NSButton] = []
    private var nativeTrafficLightGroupTrackingArea: NSTrackingArea?
    private weak var nativeTrafficLightGroupTrackingView: NSView?
    private var nativeTrafficLightGroupTrackingOptions: NSTrackingArea.Options?
    private var nativeTrafficLightGroupTrackingUserInfo: [AnyHashable: Any]?
    private var nativeTitlebarGeometry: NativeTitlebarGeometry?
    private var isUsingNativeFullScreenChrome = false
    private var windowedTitleVisibility: NSWindow.TitleVisibility?
    private var windowedTitlebarAppearsTransparent: Bool?
    private let fullScreenExitButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.image = NSImage(
            systemSymbolName: "arrow.down.right.and.arrow.up.left",
            accessibilityDescription: "Exit Full Screen"
        )
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.controlSize = .large
        button.toolTip = "Exit Full Screen"
        button.setAccessibilityLabel("Exit Full Screen")
        button.isHidden = true
        return button
    }()

    init(
        settings: SettingsService,
        accessibility: AccessibilityService,
        menuBarService: MenuBarService
    ) {
        self.settings = settings
        let preferredSize = SettingsDesign.Layout.preferredWindowSize
        if let visible = NSScreen.main?.visibleFrame {
            InterfaceScaleStore.availableWindowSize = NSSize(
                width: min(preferredSize.width, visible.width),
                height: min(preferredSize.height, visible.height)
            )
        } else {
            InterfaceScaleStore.availableWindowSize = preferredSize
        }
        let window = SettingsWindow(
            contentRect: NSRect(
                origin: .zero,
                size: SettingsDesign.Layout.windowSize
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        window.closeWithEscape = { [weak settings] in settings?.preferences.closeWithEscape == true }
        window.title = "NoMenu Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // Dragging is owned by the dedicated fixed-header region in SettingsView.
        // Content, controls, and scrollable empty space must never move the window.
        window.isMovableByWindowBackground = false
        // The window always appears at its final frame. AppKit's document-window
        // animation can begin from a system-selected origin, which made the custom
        // content look as if it slid down from the menu bar.
        window.animationBehavior = .none
        window.collectionBehavior = [.moveToActiveSpace]
        let hostingController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                accessibility: accessibility,
                menuBarService: menuBarService
            )
        )
        hostingController.sizingOptions = []
        hostingController.safeAreaRegions = []

        let containerController = NSViewController()
        let containerView = NSView(frame: NSRect(
            origin: .zero,
            size: SettingsDesign.Layout.windowSize
        ))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerController.view = containerView

        let sidebarMaterial = SettingsSidebarMaterialView(frame: NSRect(
            x: 0,
            y: 0,
            width: SettingsDesign.Layout.leftRegionWidth,
            height: SettingsDesign.Layout.windowHeight
        ))
        sidebarMaterial.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(sidebarMaterial)
        NSLayoutConstraint.activate([
            sidebarMaterial.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            sidebarMaterial.topAnchor.constraint(equalTo: containerView.topAnchor),
            sidebarMaterial.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            sidebarMaterial.widthAnchor.constraint(equalToConstant: SettingsDesign.Layout.leftRegionWidth)
        ])

        containerController.addChild(hostingController)
        hostingController.view.frame = containerView.bounds
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        containerView.addSubview(fullScreenExitButton)
        NSLayoutConstraint.activate([
            fullScreenExitButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            fullScreenExitButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            fullScreenExitButton.widthAnchor.constraint(equalToConstant: 34),
            fullScreenExitButton.heightAnchor.constraint(equalToConstant: 28)
        ])
        window.contentViewController = containerController

        var frame = window.frame
        frame.size = SettingsDesign.Layout.windowSize
        window.setFrame(frame, display: false)
        window.minSize = frame.size
        window.maxSize = frame.size
        window.center()

        super.init(window: window)
        self.sidebarMaterial = sidebarMaterial
        self.hostingView = hostingController.view
        window.delegate = self
        fullScreenExitButton.target = self
        fullScreenExitButton.action = #selector(exitFullScreen(_:))
        prepareTrafficLightPositions(in: window)
        captureNativeTitlebarGeometry()
        applyTrafficLightPositions()
        settings.$preferences
            .map(\.interfaceSize)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyInterfaceSize() }
            }
            .store(in: &preferenceObservations)
        settings.$preferences
            .map(\.language)
            .removeDuplicates()
            .sink { [weak self] language in
                let title = L10n.text("Exit Full Screen", language: language)
                self?.fullScreenExitButton.toolTip = title
                self?.fullScreenExitButton.setAccessibilityLabel(title)
                // Keep the hidden AppKit title stable; localize its accessibility
                // name without resetting the native titlebar layout.
                self?.window?.setAccessibilityLabel(language == .korean ? "NoMenu 설정" : "NoMenu Settings")
            }
            .store(in: &preferenceObservations)
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func applyInterfaceSize() {
        // Only content metrics change. Structural bounds stay owned by Auto Layout.
        window?.contentView?.needsLayout = true
    }

    func show() {
        // Accessory applications are hidden as a whole when another app activates.
        // Temporarily adopt the normal window policy so Settings behaves like the
        // reference: it stays visible behind other apps and closes independently.
        guard let window else { return }
        let shouldAnimatePresentation = !window.isVisible
        if shouldAnimatePresentation {
            // Establish and render the final geometry while the window is hidden.
            window.center()
            applyTrafficLightPositions()
            window.alphaValue = 0
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            applyTrafficLightPositions()
        }

        NSApp.setActivationPolicy(.regular)
        // Changing activation policy rebuilds the application menu. Present on the
        // next run-loop turn so that rebuild cannot swallow the ordering request.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, let window = self.window else { return }
            self.applyTrafficLightPositions()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            self.applyTrafficLightPositions()

            guard shouldAnimatePresentation else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = self.settings.animationsAllowed ? 0.12 : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyTrafficLightPositions()
    }

    func windowDidResize(_ notification: Notification) {
        applyTrafficLightPositions()
    }

    func windowDidUpdate(_ notification: Notification) {
        // AppKit may lay out its chrome after a localized content update.
        // Reuse the existing native frame and tracking alignment at that lifecycle boundary.
        applyTrafficLightPositions()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        guard let window else { return }
        isUsingNativeFullScreenChrome = true
        windowedTitleVisibility = window.titleVisibility
        windowedTitlebarAppearsTransparent = window.titlebarAppearsTransparent
        restoreNativeTitlebarGeometry()
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        fullScreenExitButton.isHidden = false
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        fullScreenExitButton.isHidden = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window else { return }
        restoreWindowedTitlebarConfiguration(in: window)
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        isUsingNativeFullScreenChrome = false
        applyTrafficLightPositions()
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        restoreWindowedTitlebarConfiguration(in: window)
        fullScreenExitButton.isHidden = true
        isUsingNativeFullScreenChrome = false
        applyTrafficLightPositions()
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        fullScreenExitButton.isHidden = false
    }

    @objc private func exitFullScreen(_ sender: Any?) {
        guard isUsingNativeFullScreenChrome else { return }
        window?.toggleFullScreen(sender)
    }

    private func restoreWindowedTitlebarConfiguration(in window: NSWindow) {
        if let windowedTitleVisibility {
            window.titleVisibility = windowedTitleVisibility
        }
        if let windowedTitlebarAppearsTransparent {
            window.titlebarAppearsTransparent = windowedTitlebarAppearsTransparent
        }
        windowedTitleVisibility = nil
        windowedTitlebarAppearsTransparent = nil
    }

    private func prepareTrafficLightPositions(in window: NSWindow) {
        trafficLightButtons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }
    }

    private func captureNativeTitlebarGeometry() {
        guard let titlebarView = trafficLightButtons.first?.superview,
              let titlebarContainer = titlebarView.superview
        else { return }
        nativeTitlebarGeometry = NativeTitlebarGeometry(
            titlebarView: titlebarView,
            titlebarViewFrame: titlebarView.frame,
            titlebarContainer: titlebarContainer,
            titlebarContainerFrame: titlebarContainer.frame,
            buttonFrames: trafficLightButtons.map(\.frame)
        )
    }

    private func restoreNativeTitlebarGeometry() {
        guard let geometry = nativeTitlebarGeometry,
              geometry.buttonFrames.count == trafficLightButtons.count
        else { return }
        geometry.titlebarContainer.frame = geometry.titlebarContainerFrame
        geometry.titlebarView.frame = geometry.titlebarViewFrame
        for (button, frame) in zip(trafficLightButtons, geometry.buttonFrames) {
            button.frame = frame
        }
        if let frameView = geometry.titlebarContainer.superview {
            alignNativeTrafficLightHoverTracking(in: frameView)
        }
    }

    private func applyTrafficLightPositions() {
        guard !isUsingNativeFullScreenChrome else { return }
        guard let contentView = window?.contentView,
              let frameView = contentView.superview,
              trafficLightButtons.count == SettingsDesign.Layout.trafficLightCenters.count
        else { return }

        expandNativeTitlebarHitRegion(in: frameView, contentView: contentView)

        for (button, targetCenter) in zip(
            trafficLightButtons,
            SettingsDesign.Layout.trafficLightCenters
        ) {
            guard let buttonSuperview = button.superview else { continue }
            let centerInContent = NSPoint(
                x: targetCenter.x,
                y: contentView.isFlipped
                    ? targetCenter.y
                    : contentView.bounds.height - targetCenter.y
            )
            let centerInSuperview = buttonSuperview.convert(
                centerInContent,
                from: contentView
            )
            let desiredOrigin = NSPoint(
                x: centerInSuperview.x - (button.frame.width / 2),
                y: centerInSuperview.y - (button.frame.height / 2)
            )
            if button.frame.origin != desiredOrigin {
                button.setFrameOrigin(desiredOrigin)
            }
        }

        alignNativeTrafficLightHoverTracking(in: frameView)
    }

    private func alignNativeTrafficLightHoverTracking(in frameView: NSView) {
        let visibleButtonFrames = trafficLightButtons.map {
            frameView.convert($0.bounds, from: $0)
        }
        guard let firstFrame = visibleButtonFrames.first else { return }
        let finalTrackingRect = visibleButtonFrames.dropFirst().reduce(firstFrame) {
            $0.union($1)
        }

        // AppKit installs the shared native traffic-light hover tracker on
        // NSThemeFrame before NoMenu moves the real standard buttons. Moving the
        // NSButtons updates click hit-testing (and the zoom cell's own tracker),
        // but AppKit leaves this group tracker at its original title-bar rect.
        // Preserve its native owner/options and only rebuild its rect from the
        // buttons' final real frames, so the standard hover symbols remain native.
        let existingReplacement = nativeTrafficLightGroupTrackingArea
        let nativeGroupAreas = frameView.trackingAreas.filter { area in
            guard area !== existingReplacement,
                  area.options.contains(.mouseEnteredAndExited),
                  area.options.contains(.activeAlways),
                  !area.options.contains(.mouseMoved),
                  !area.options.contains(.cursorUpdate),
                  let owner = area.owner as AnyObject?
            else { return false }
            return owner === frameView
        }

        if let nativeArea = nativeGroupAreas.first {
            nativeTrafficLightGroupTrackingOptions = nativeArea.options
            nativeTrafficLightGroupTrackingUserInfo = nativeArea.userInfo
        }

        for staleArea in nativeGroupAreas {
            frameView.removeTrackingArea(staleArea)
        }

        if let existingReplacement,
           nativeTrafficLightGroupTrackingView === frameView,
           frameView.trackingAreas.contains(where: { $0 === existingReplacement }),
           existingReplacement.rect == finalTrackingRect {
            return
        }

        if let existingReplacement,
           let previousView = nativeTrafficLightGroupTrackingView {
            previousView.removeTrackingArea(existingReplacement)
        }

        guard let options = nativeTrafficLightGroupTrackingOptions else { return }
        let alignedArea = NSTrackingArea(
            rect: finalTrackingRect,
            options: options,
            owner: frameView,
            userInfo: nativeTrafficLightGroupTrackingUserInfo
        )
        frameView.addTrackingArea(alignedArea)
        nativeTrafficLightGroupTrackingArea = alignedArea
        nativeTrafficLightGroupTrackingView = frameView
    }

    private func expandNativeTitlebarHitRegion(
        in frameView: NSView,
        contentView: NSView
    ) {
        guard let titlebarView = trafficLightButtons.first?.superview,
              let titlebarContainer = titlebarView.superview,
              titlebarContainer.superview === frameView
        else { return }

        let lowestButtonEdge = zip(
            trafficLightButtons,
            SettingsDesign.Layout.trafficLightCenters
        ).map { button, targetCenter -> CGFloat in
            let centerInContent = NSPoint(
                x: targetCenter.x,
                y: contentView.isFlipped
                    ? targetCenter.y
                    : contentView.bounds.height - targetCenter.y
            )
            let centerInFrameView = frameView.convert(centerInContent, from: contentView)
            return centerInFrameView.y - (button.frame.height / 2)
        }.min() ?? titlebarContainer.frame.minY

        var containerFrame = titlebarContainer.frame
        let topEdge = containerFrame.maxY
        containerFrame.origin.y = min(containerFrame.minY, lowestButtonEdge)
        containerFrame.size.height = topEdge - containerFrame.minY
        if titlebarContainer.frame != containerFrame {
            titlebarContainer.frame = containerFrame
        }
        if titlebarView.frame != titlebarContainer.bounds {
            titlebarView.frame = titlebarContainer.bounds
        }
    }

}

private final class SettingsSidebarMaterialView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .sidebar
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = SettingsDesign.Layout.outerCornerRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        nil
    }
}
