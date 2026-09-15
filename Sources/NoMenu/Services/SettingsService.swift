import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog
import ServiceManagement

@MainActor
protocol LoginItemControlling: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
protocol UpdateChecking: AnyObject {
    func setAutomaticChecksEnabled(_ enabled: Bool)
    func checkForUpdates() async throws
}

@MainActor
private final class SystemLoginItemController: LoginItemControlling {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class SettingsService: ObservableObject {
    @Published private(set) var preferences: SettingsPreferences
    @Published private(set) var selectedSection: SettingsSection = .general
    @Published var actionMessage: String?
    @Published var shortcutError: String?
    var diagnosticReportProvider: (() -> String)?
    var shortcutRegistrar: ((NoMenuShortcut?) throws -> Void)?
    var shortcutRecordingChanged: ((Bool) -> Void)?
    private let preferencesKey = "settingsPreferencesV1"
    @Published private(set) var launchAtLoginStatus: SMAppService.Status
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var automaticUpdateChecksEnabled: Bool
    @Published private(set) var openNoMenuOnLaunch: Bool
    @Published private(set) var hoverHighlightEnabled: Bool
    @Published private(set) var ignoredItemIDs: Set<String>
    @Published private(set) var screenRecordingAuthorized: Bool
    @Published private(set) var updateCheckInProgress = false
    private(set) var hasRequestedAccessibilityPermission: Bool

    private let defaults: UserDefaults
    private let loginItem: LoginItemControlling
    private let updateChecker: UpdateChecking?
    private let requestedAccessibilityKey = "hasRequestedAccessibilityPermission"
    private let launchAtLoginChoiceKey = "launchAtLoginUserChoice"
    private let defaultRegistrationAttemptKey = "hasAttemptedDefaultLaunchAtLoginRegistration"
    private let automaticUpdatesKey = "checkForUpdatesAutomatically"
    private let openOnLaunchKey = "openNoMenuOnLaunch"
    private let hoverHighlightKey = "hoverHighlightEnabled"
    private let ignoredItemsKey = "ignoredMenuBarItemIDs"
    private let logger = Logger(subsystem: "com.nomenu.utility", category: "Lifecycle")
    private var lastLoggedScreenRecordingState: Bool?

    init(defaults: UserDefaults = .standard, updateChecker: UpdateChecking? = nil) {
        let loginItem = SystemLoginItemController()
        self.defaults = defaults
        let loadedPreferences = Self.loadPreferences(defaults)
        preferences = loadedPreferences
        InterfaceScaleStore.current = loadedPreferences.interfaceSize.scale
        LocalizationStore.current = loadedPreferences.language
        self.loginItem = loginItem
        self.updateChecker = updateChecker
        launchAtLoginStatus = loginItem.status
        hasRequestedAccessibilityPermission = defaults.bool(forKey: requestedAccessibilityKey)
        automaticUpdateChecksEnabled = Self.preference(
            defaults,
            key: automaticUpdatesKey,
            defaultValue: true
        )
        openNoMenuOnLaunch = defaults.bool(forKey: openOnLaunchKey)
        hoverHighlightEnabled = Self.preference(
            defaults,
            key: hoverHighlightKey,
            defaultValue: true
        )
        ignoredItemIDs = Set(defaults.stringArray(forKey: ignoredItemsKey) ?? [])
        screenRecordingAuthorized = CGPreflightScreenCaptureAccess()
    }

    init(
        defaults: UserDefaults,
        loginItem: LoginItemControlling,
        updateChecker: UpdateChecking? = nil
    ) {
        self.defaults = defaults
        let loadedPreferences = Self.loadPreferences(defaults)
        preferences = loadedPreferences
        InterfaceScaleStore.current = loadedPreferences.interfaceSize.scale
        LocalizationStore.current = loadedPreferences.language
        self.loginItem = loginItem
        self.updateChecker = updateChecker
        launchAtLoginStatus = loginItem.status
        hasRequestedAccessibilityPermission = defaults.bool(forKey: requestedAccessibilityKey)
        automaticUpdateChecksEnabled = Self.preference(
            defaults,
            key: automaticUpdatesKey,
            defaultValue: true
        )
        openNoMenuOnLaunch = defaults.bool(forKey: openOnLaunchKey)
        hoverHighlightEnabled = Self.preference(
            defaults,
            key: hoverHighlightKey,
            defaultValue: true
        )
        ignoredItemIDs = Set(defaults.stringArray(forKey: ignoredItemsKey) ?? [])
        screenRecordingAuthorized = CGPreflightScreenCaptureAccess()
    }

    var launchAtLoginEnabled: Bool {
        launchAtLoginStatus == .enabled
    }

    var launchAtLoginRequiresApproval: Bool {
        launchAtLoginStatus == .requiresApproval
    }

    var launchAtLoginStatusDescription: String {
        switch launchAtLoginStatus {
        case .enabled:
            return localized("Enabled — NoMenu will start at the next login.")
        case .requiresApproval:
            return localized("Approval required in System Settings › General › Login Items.")
        case .notRegistered:
            return localized("Disabled — NoMenu will not start automatically.")
        case .notFound:
            return localized("Unavailable for this application location or build.")
        @unknown default:
            return localized("Current login-item status is unavailable.")
        }
    }

    func configureDefaultLaunchAtLoginIfNeeded() {
        refreshLaunchAtLoginStatus()

        // An explicit user choice always wins. In particular, a previous Off choice
        // must never be silently reversed on a later launch.
        guard defaults.object(forKey: launchAtLoginChoiceKey) == nil,
              !defaults.bool(forKey: defaultRegistrationAttemptKey) else { return }
        defaults.set(true, forKey: defaultRegistrationAttemptKey)

        guard launchAtLoginStatus == .notRegistered else {
            logger.notice("default login registration skipped; status=\(String(describing: self.launchAtLoginStatus), privacy: .public)")
            return
        }

        do {
            try loginItem.register()
            refreshLaunchAtLoginStatus()
            logger.notice("default login registration requested; status=\(String(describing: self.launchAtLoginStatus), privacy: .public)")
        } catch {
            recordLaunchAtLoginError(error)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        defaults.set(enabled, forKey: launchAtLoginChoiceKey)
        launchAtLoginError = nil
        refreshLaunchAtLoginStatus()

        do {
            if enabled {
                switch launchAtLoginStatus {
                case .enabled:
                    break
                case .requiresApproval:
                    loginItem.openSystemSettings()
                case .notRegistered, .notFound:
                    try loginItem.register()
                @unknown default:
                    try loginItem.register()
                }
            } else if launchAtLoginStatus != .notRegistered {
                try loginItem.unregister()
            }
            refreshLaunchAtLoginStatus()
            logger.notice("user set Launch at Login to \(enabled, privacy: .public); actual status=\(String(describing: self.launchAtLoginStatus), privacy: .public)")
        } catch {
            recordLaunchAtLoginError(error)
            throw error
        }
    }

    func refreshLaunchAtLoginStatus() {
        let current = loginItem.status
        if launchAtLoginStatus != current {
            launchAtLoginStatus = current
        }
    }

    func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }

    func clearLaunchAtLoginError() {
        launchAtLoginError = nil
    }

    func setAutomaticUpdateChecks(_ enabled: Bool) {
        automaticUpdateChecksEnabled = enabled
        defaults.set(enabled, forKey: automaticUpdatesKey)
        updateChecker?.setAutomaticChecksEnabled(enabled)
        logger.notice("automatic update checks set to \(enabled, privacy: .public)")
    }

    func checkForUpdatesNow() {
        guard !updateCheckInProgress else { return }
        guard let updateChecker else {
            logger.notice("manual update check requested; no updater backend is configured")
            actionMessage = localized("No update service is configured for this development build.")
            return
        }
        updateCheckInProgress = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { updateCheckInProgress = false }
            do {
                try await updateChecker.checkForUpdates()
            } catch {
                actionMessage = "\(localized("Update check failed:")) \(error.localizedDescription)"
                logger.error("manual update check failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func setOpenNoMenuOnLaunch(_ enabled: Bool) {
        openNoMenuOnLaunch = enabled
        defaults.set(enabled, forKey: openOnLaunchKey)
    }

    func setHoverHighlight(_ enabled: Bool) {
        hoverHighlightEnabled = enabled
        defaults.set(enabled, forKey: hoverHighlightKey)
    }

    func resetIgnoredItems() {
        ignoredItemIDs = []
        defaults.removeObject(forKey: ignoredItemsKey)
    }

    func refreshRuntimeState() {
        refreshLaunchAtLoginStatus()
        refreshScreenRecordingStatus()
    }

    func refreshScreenRecordingStatus() {
        let current = CGPreflightScreenCaptureAccess()
        if screenRecordingAuthorized != current {
            screenRecordingAuthorized = current
        }
        if lastLoggedScreenRecordingState != current {
            lastLoggedScreenRecordingState = current
            logger.notice("[ScreenRecordingPermission] PID=\(ProcessInfo.processInfo.processIdentifier) executable=\(Bundle.main.executableURL?.path ?? "unknown", privacy: .public) bundleID=\(Bundle.main.bundleIdentifier ?? "unknown", privacy: .public) preflight=\(current) published=\(self.screenRecordingAuthorized) Settings=\(self.screenRecordingAuthorized) LiveArtwork=\(self.screenRecordingAuthorized)")
        }
    }

    func openAccessibilitySettings() {
        openPrivacyPane(anchor: "Privacy_Accessibility")
    }

    func requestOrOpenScreenRecordingSettings() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        refreshScreenRecordingStatus()
        openPrivacyPane(anchor: "Privacy_ScreenCapture")
    }

    func markAccessibilityPermissionRequested() {
        hasRequestedAccessibilityPermission = true
        defaults.set(true, forKey: requestedAccessibilityKey)
    }

    var animationsAllowed: Bool {
        preferences.animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func updatePreferences(_ change: (inout SettingsPreferences) -> Void) {
        var next = preferences
        change(&next)
        guard next != preferences else { return }
        InterfaceScaleStore.current = next.interfaceSize.scale
        LocalizationStore.current = next.language
        preferences = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: preferencesKey) }
    }

    func resetBarAppearanceAndLayout() {
        updatePreferences { $0.resetBarAppearanceAndLayout() }
    }

    var language: AppLanguage { preferences.language }

    func localized(_ key: String) -> String {
        L10n.text(key, language: preferences.language)
    }

    func prepareSettingsPresentation() {
        selectedSection = preferences.rememberLastPage ? preferences.lastPage : .general
        refreshRuntimeState()
    }

    func selectSection(_ section: SettingsSection) {
        selectedSection = section
        updatePreferences { $0.lastPage = section }
    }

    func recordUse(of item: MenuBarItem) {
        updatePreferences {
            $0.recentlyUsed.removeAll { $0 == item.stableIdentity }
            $0.recentlyUsed.insert(item.stableIdentity, at: 0)
            $0.recentlyUsed = Array($0.recentlyUsed.prefix(100))
        }
    }

    func setShortcut(_ shortcut: NoMenuShortcut?) {
        do {
            guard let shortcutRegistrar else {
                shortcutError = localized("Shortcut registration is not available yet.")
                return
            }
            try shortcutRegistrar(shortcut)
            shortcutError = nil
            updatePreferences { $0.shortcut = shortcut }
        } catch { shortcutError = error.localizedDescription }
    }

    var versionInfo: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unavailable"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unavailable"
        return "NoMenu \(version) (\(build))\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func resetNoMenuState() throws {
        // Only explicit NoMenu-owned keys, never the entire defaults domain or TCC.
        // Unregister first so a failure does not leave the UI claiming login is off.
        try setLaunchAtLogin(false)
        try shortcutRegistrar?(nil)
        for key in [preferencesKey, automaticUpdatesKey, openOnLaunchKey,
                    hoverHighlightKey, ignoredItemsKey] { defaults.removeObject(forKey: key) }
        preferences = SettingsPreferences()
        selectedSection = .general
        setAutomaticUpdateChecks(true)
        setOpenNoMenuOnLaunch(false)
        setHoverHighlight(true)
        resetIgnoredItems()
        shortcutError = nil
        // Keep the first-request/default-registration markers: reset is not a
        // request to prompt for permissions or re-enable login next launch.
    }

    private static func loadPreferences(_ defaults: UserDefaults) -> SettingsPreferences {
        guard let data = defaults.data(forKey: "settingsPreferencesV1"),
              let value = try? JSONDecoder().decode(SettingsPreferences.self, from: data)
        else { return SettingsPreferences() }
        return value
    }

    private func recordLaunchAtLoginError(_ error: Error) {
        refreshLaunchAtLoginStatus()
        launchAtLoginError = error.localizedDescription
        logger.error("Launch at Login operation failed: \(error.localizedDescription, privacy: .public); actual status=\(String(describing: self.launchAtLoginStatus), privacy: .public)")
    }

    private func openPrivacyPane(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func preference(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }
}
