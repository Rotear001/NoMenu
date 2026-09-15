import AppKit
import Combine
import OSLog
import Security

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let accessibilityService = AccessibilityService()
    let settingsService = SettingsService()
    private let shortcutService = ShortcutService()
    lazy var menuBarService = MenuBarService(
        accessibility: accessibilityService,
        settings: settingsService,
        ignoredItemIDs: settingsService.ignoredItemIDs,
        hoverHighlightEnabled: settingsService.hoverHighlightEnabled
    )

    private var statusItem: NSStatusItem?
    private var statusItemIsActive = false
    private var fallbackRefreshTimer: Timer?
    private var scheduledRefresh: Task<Void, Never>?
    private var permissionUIReportedVisible = false
    private var languageObservation: AnyCancellable?
    private let logger = Logger(subsystem: "com.nomenu.utility", category: "Accessibility")
    private lazy var panelController = PanelController(
        service: menuBarService,
        accessibility: accessibilityService,
        statusButtonProvider: { [weak self] in self?.statusItem?.button },
        onPresentationStateChange: { [weak self] _ in
            self?.refreshStatusItemHighlight()
        }
    )
    private lazy var settingsWindowController = SettingsWindowController(
        settings: settingsService,
        accessibility: accessibilityService,
        menuBarService: menuBarService
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        logger.notice("runtime identity bundle=\(Bundle.main.bundleIdentifier ?? "unknown", privacy: .public); executable=\(Bundle.main.executableURL?.path ?? "unknown", privacy: .public)")
        settingsService.configureDefaultLaunchAtLoginIfNeeded()
        configureSettingsActions()
        createStatusItems()
        languageObservation = settingsService.$preferences
            .map(\.language)
            .removeDuplicates()
            .sink { [weak self] language in
                self?.statusItem?.button?.toolTip = L10n.text("NoMenu — show menu bar items", language: language)
                self?.connectApplicationSettingsMenu()
            }
        MenuBarClickDiagnostics.shared.start { [weak self] in
            guard let self else { return "app delegate released" }
            return self.panelController.clickDiagnosticState
        }
        accessibilityService.onMenuBarChange = { [weak self] in
            self?.scheduleRefresh(after: .milliseconds(120))
        }
        accessibilityService.onTrustChange = { [weak self] previous, current in
            self?.accessibilityTrustDidChange(from: previous, to: current)
        }
        accessibilityService.onPermissionRequested = { [weak self] in
            self?.beginPermissionPollingIfNeeded()
        }
        observeLifecycleChanges()

        // Refresh the process's real TCC state before the persistent SwiftUI panel
        // is created. This prevents a stale cached false value from ever becoming
        // the panel's first permission-dependent frame.
        let cachedTrusted = accessibilityService.isTrusted
        let trusted = accessibilityService.refreshAccessibilityState(reason: "application startup")
        logger.notice("startup trust; cached trusted: \(cachedTrusted, privacy: .public); runtime trusted: \(trusted, privacy: .public); published trusted: \(self.accessibilityService.isTrusted, privacy: .public)")
        if cachedTrusted == trusted {
            if trusted {
                accessibilityDidBecomeAvailable()
            } else {
                accessibilityDidBecomeUnavailable()
            }
        }
        if !trusted {
            logRuntimeIdentity(reason: "application startup")
        }
        fallbackRefreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performFallbackRefresh() }
        }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.connectApplicationSettingsMenu()
        }
        openPanelForManualLaunchIfNeeded(notification)
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcutService.stop()
        MenuBarClickDiagnostics.shared.stop()
        scheduledRefresh?.cancel()
        fallbackRefreshTimer?.invalidate()
        stopPermissionPolling()
        accessibilityService.stopAccessibilityServices()
        panelController.hide()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        logger.notice("application became active")
        settingsService.refreshRuntimeState()
        let wasTrusted = accessibilityService.isTrusted
        let trusted = accessibilityService.refreshAccessibilityState(reason: "application became active")
        if trusted && wasTrusted {
            refreshDiscoveredMenuBarItems()
        } else {
            if !trusted { beginPermissionPollingIfNeeded() }
        }
    }

    @objc private func togglePanel() {
        MenuBarClickDiagnostics.record("status-item-action", event: NSApp.currentEvent)
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            refreshAccessibilityStateForPanelPresentation()
            panelController.toggle(relativeTo: statusItem?.button)
        }
    }

    private func refreshAccessibilityStateForPanelPresentation() {
        let cachedTrusted = accessibilityService.isTrusted
        let runtimeTrusted = accessibilityService.refreshAccessibilityState(reason: "menu requested")
        let publishedTrusted = accessibilityService.isTrusted
        let presentation = runtimeTrusted ? "normal content" : "permission UI"

        if runtimeTrusted {
            // A true result must retire the temporary permission timer even when
            // no transition callback was needed because the cache was already true.
            stopPermissionPolling()
        } else {
            beginPermissionPollingIfNeeded()
            logRuntimeIdentity(reason: "menu requested")
        }

        // Resolve the already-retained hosting hierarchy with the freshly published
        // value before orderFront starts the existing panel animation.
        panelController.prepare(relativeTo: statusItem?.button)
        logger.notice("menu requested; cached trusted: \(cachedTrusted, privacy: .public); runtime trusted: \(runtimeTrusted, privacy: .public); published trusted: \(publishedTrusted, privacy: .public); presentation: \(presentation, privacy: .public)")
    }

    private func refreshStatusItemHighlight() {
        let isActive = panelController.presentationState.isActive
        guard statusItemIsActive != isActive else { return }
        statusItemIsActive = isActive
        statusItem?.button?.state = isActive ? .on : .off
        statusItem?.button?.highlight(isActive)

        // NSStatusBarButton finishes its native mouse-up tracking after invoking the
        // action. Re-apply from the authoritative panel state on the next run-loop
        // turn so AppKit's tracking cleanup cannot clear an active/open highlight.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let stillActive = self.panelController.presentationState.isActive
            self.statusItem?.button?.state = stillActive ? .on : .off
            self.statusItem?.button?.highlight(stillActive)
        }
    }

    @objc private func refreshMenuBarItems() {
        let wasTrusted = accessibilityService.isTrusted
        guard accessibilityService.refreshAccessibilityState(reason: "menu bar refresh") else {
            if !wasTrusted { accessibilityDidBecomeUnavailable() }
            return
        }
        // The false-to-true callback owns first-time pipeline startup and its forced
        // discovery pass. Avoid a second concurrent refresh on the same transition.
        guard wasTrusted else { return }
        refreshDiscoveredMenuBarItems()
    }

    private func refreshDiscoveredMenuBarItems() {
        guard accessibilityService.isTrusted else { return }
        menuBarService.refresh()
        // When hidden, eagerly resolve any SwiftUI changes caused by discovery so
        // they cannot become first-frame work on the next presentation.
        panelController.prepare(relativeTo: statusItem?.button)
        panelController.displayConfigurationRefreshCompleted()
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func quitNoMenu() {
        NSApp.terminate(nil)
    }

    private func createStatusItems() {
        // NoMenu owns only this status item; every other menu-bar element is read-only.
        let item = NSStatusBar.system.statusItem(withLength: 34)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "ellipsis",
                accessibilityDescription: "NoMenu"
            )
            button.image?.isTemplate = true
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(togglePanel)
            // Opening/closing begins with the physical press. Mouse-up is not an
            // action event, so releasing this same click cannot toggle a second time.
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
            button.toolTip = settingsService.localized("NoMenu — show menu bar items")
            button.setAccessibilityLabel("NoMenu")
        }
        statusItem = item
    }

    private func observeLifecycleChanges() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationsChanged(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationsChanged(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationsChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func workspaceApplicationsChanged(_ notification: Notification) {
        scheduleRefresh(after: .milliseconds(180))
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        // Screen objects and absolute menu-bar coordinates are replaced by
        // WindowServer during rotation/configuration changes. Invalidate panel
        // geometry synchronously, then let the existing settled refresh rebuild
        // AX item frames from the new configuration.
        panelController.screenParametersDidChange()
        scheduleRefresh(after: .milliseconds(180))
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        // A panel that was logically open on the previous Space must not make the
        // first status-item click on this Space take the close branch. Keep the
        // retained panel/hosting hierarchy, but retire every transient presentation
        // object and defer screen/anchor resolution until the next physical click.
        panelController.activeSpaceDidChange()
        scheduleRefresh(after: .milliseconds(180))
    }

    private func scheduleRefresh(after delay: Duration) {
        guard accessibilityService.isTrusted else {
            beginPermissionPollingIfNeeded()
            return
        }
        scheduledRefresh?.cancel()
        scheduledRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.refreshDiscoveredMenuBarItems()
        }
    }

    private func accessibilityTrustDidChange(from previous: Bool, to current: Bool) {
        if current {
            accessibilityDidBecomeAvailable()
        } else {
            accessibilityDidBecomeUnavailable()
        }
    }

    private func accessibilityDidBecomeAvailable() {
        stopPermissionPolling()
        if permissionUIReportedVisible {
            permissionUIReportedVisible = false
            logger.notice("permission UI removed")
        }
        logger.notice("starting Accessibility-dependent pipeline")
        menuBarService.refresh(force: true)
        panelController.prepare(relativeTo: statusItem?.button)
    }

    private func accessibilityDidBecomeUnavailable() {
        scheduledRefresh?.cancel()
        scheduledRefresh = nil
        accessibilityService.stopAccessibilityServices()
        menuBarService.accessibilityDidBecomeUnavailable()
        if !permissionUIReportedVisible {
            permissionUIReportedVisible = true
            logger.notice("permission UI shown")
        }
        panelController.prepare(relativeTo: statusItem?.button)
        beginPermissionPollingIfNeeded()
    }

    private func beginPermissionPollingIfNeeded() {
        accessibilityService.beginPermissionPollingIfNeeded()
    }

    private func stopPermissionPolling() {
        accessibilityService.stopPermissionPolling()
    }

    private func logRuntimeIdentity(reason: String) {
        let bundlePath = Bundle.main.bundleURL.path
        let executablePath = Bundle.main.executableURL?.path ?? "unknown"
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
        let signingIdentity = currentSigningIdentity()
        logger.error("\(reason, privacy: .public); AXIsProcessTrusted() is false; bundle path: \(bundlePath, privacy: .public); executable: \(executablePath, privacy: .public); bundle identifier: \(bundleIdentifier, privacy: .public); signing identity: \(signingIdentity, privacy: .public)")
    }

    private func currentSigningIdentity() -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else {
            return "unavailable"
        }

        var rawInformation: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &rawInformation) == errSecSuccess,
              let information = rawInformation as? [String: Any] else {
            return "unavailable"
        }

        let identifier = information[kSecCodeInfoIdentifier as String] as? String ?? "unknown"
        let teamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String ?? "none"
        let certificateName: String
        if let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let certificate = certificates.first,
           let subject = SecCertificateCopySubjectSummary(certificate) {
            certificateName = subject as String
        } else {
            certificateName = "ad-hoc/no certificate"
        }
        return "identifier=\(identifier); team=\(teamIdentifier); certificate=\(certificateName)"
    }

    private func performFallbackRefresh() {
        // This timer refreshes menu-bar contents, not Accessibility permission.
        refreshDiscoveredMenuBarItems()
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        let refresh = NSMenuItem(
            title: settingsService.localized("Refresh Overflow Items"),
            action: #selector(refreshMenuBarItems),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(
            title: settingsService.localized("NoMenu Settings…"),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: settingsService.localized("Quit NoMenu"),
            action: #selector(quitNoMenu),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    private func openSettings() {
        _ = accessibilityService.refreshAccessibilityState(reason: "Settings requested")
        settingsService.prepareSettingsPresentation()
        panelController.hide()
        settingsWindowController.show()
    }

    private func configureSettingsActions() {
        shortcutService.onPress = { [weak self] in
            guard let self else { return }
            self.refreshAccessibilityStateForPanelPresentation()
            self.panelController.toggle(relativeTo: self.statusItem?.button)
        }
        settingsService.shortcutRegistrar = { [weak self] shortcut in
            try self?.shortcutService.register(shortcut)
        }
        settingsService.shortcutRecordingChanged = { [weak self] recording in
            guard let self else { return }
            if recording { self.shortcutService.stop() }
            else {
                do { try self.shortcutService.register(self.settingsService.preferences.shortcut) }
                catch { self.settingsService.shortcutError = error.localizedDescription }
            }
        }
        do { try shortcutService.register(settingsService.preferences.shortcut) }
        catch { settingsService.shortcutError = error.localizedDescription }
        menuBarService.onActivationCompleted = { [weak self] in
            guard let self else { return }
            self.panelController.keepOpenAfterActivation()
        }
        settingsService.diagnosticReportProvider = { [weak self] in
            guard let self else { return "NoMenu diagnostics unavailable" }
            let trusted = self.accessibilityService.refreshAccessibilityState(reason: "diagnostic report")
            self.settingsService.refreshScreenRecordingStatus()
            return """
            \(self.settingsService.versionInfo)
            Bundle ID: \(Bundle.main.bundleIdentifier ?? self.settingsService.localized("Unavailable"))
            \(self.settingsService.localized("Accessibility")): \(self.settingsService.localized(trusted ? "Granted" : "Not Granted"))
            \(self.settingsService.localized("Screen Recording")): \(self.settingsService.localized(self.settingsService.screenRecordingAuthorized ? "Granted" : "Not Granted"))
            \(self.settingsService.localized("Detected Items")): \(self.menuBarService.items.count)
            \(self.settingsService.localized("Overflowed Items")): \(self.menuBarService.overflowItems.count)
            \(self.settingsService.localized("Ignored Items")): \(self.settingsService.ignoredItemIDs.count)
            Discovery: \(self.menuBarService.discoveryState)
            AX observers: \(self.accessibilityService.observerCount)
            Permission polling: \(self.accessibilityService.isPermissionPolling)
            External interaction polling: \(self.menuBarService.isExternalInteractionPolling)
            Active NoMenu panels: \(self.panelController.activePanelCount)
            Active NoMenu event monitors: \(self.panelController.activeEventMonitorCount + self.menuBarService.activeInteractionMonitorCount + MenuBarClickDiagnostics.shared.activeMonitorCount)
            Shortcut registrations: \(self.shortcutService.registrationCount)
            Displays: \(NSScreen.screens.count)
            """
        }
    }

    func showSettingsWindow() {
        openSettings()
    }

    private func connectApplicationSettingsMenu() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let settingsItem = appMenu.items.first(where: {
                  $0.keyEquivalent == "," || $0.title.hasPrefix("Settings")
              }) else { return }
        settingsItem.target = self
        settingsItem.action = #selector(openSettingsFromMenu)
        settingsItem.title = settingsService.localized("Settings…")
    }

    private func openPanelForManualLaunchIfNeeded(_ notification: Notification) {
        guard settingsService.openNoMenuOnLaunch else { return }
        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey]
            as? NSNumber)?.boolValue ?? false
        let isForegroundLaunch = NSApp.isActive
            || NSWorkspace.shared.frontmostApplication?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier
        guard isDefaultLaunch, isForegroundLaunch else {
            logger.notice("Open NoMenu on Launch skipped for quiet/background launch")
            return
        }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.panelController.show(relativeTo: self.statusItem?.button)
        }
    }
}
