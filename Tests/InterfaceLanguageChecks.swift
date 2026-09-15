import AppKit
import ServiceManagement

final class InterfaceLanguageDefaults: UserDefaults, @unchecked Sendable {
    var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
}

@MainActor
final class InterfaceLanguageLogin: LoginItemControlling {
    var status: SMAppService.Status = .notRegistered
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}

@MainActor
func runInterfaceLanguageChecks() throws {
    _ = NSApplication.shared
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOMENU_SETTINGS_SNAPSHOT_DIR"]!)
    let localizationBundleURL = output.appendingPathComponent("Localization.bundle")
    let localizationResources = localizationBundleURL.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(at: localizationResources, withIntermediateDirectories: true)
    let sourceRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOMENU_TEST_ICON"]!)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/NoMenu/Resources")
    for language in ["en", "ko"] {
        try FileManager.default.copyItem(
            at: sourceRoot.appendingPathComponent("\(language).lproj"),
            to: localizationResources.appendingPathComponent("\(language).lproj")
        )
    }
    let info: [String: Any] = ["CFBundleIdentifier": "com.nomenu.localization-tests",
                               "CFBundleDevelopmentRegion": "en"]
    let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try infoData.write(to: localizationBundleURL.appendingPathComponent("Contents/Info.plist"))
    guard let localizationBundle = Bundle(path: localizationBundleURL.path) else { fatalError("Missing localization bundle") }
    L10n.resourceBundleOverride = localizationBundle
    defer { L10n.resourceBundleOverride = nil }
    let defaults = InterfaceLanguageDefaults()
    let settings = SettingsService(defaults: defaults, loginItem: InterfaceLanguageLogin())
    assert(settings.preferences.interfaceSize == .defaultSize)
    settings.updatePreferences {
        $0.interfaceSize = .large
        $0.language = .korean
    }
    let restored = SettingsService(defaults: defaults, loginItem: InterfaceLanguageLogin())
    assert(restored.preferences.interfaceSize == .large)
    assert(restored.preferences.language == .korean)

    settings.updatePreferences {
        $0.interfaceSize = .defaultSize
        $0.language = .english
    }
    let accessibility = AccessibilityService(trustProvider: { false })
    defer { accessibility.stopPermissionPolling() }
    let service = MenuBarService(accessibility: accessibility, settings: settings)
    let controller = SettingsWindowController(settings: settings, accessibility: accessibility,
                                               menuBarService: service)
    guard let window = controller.window, let view = window.contentView else { fatalError("Missing window") }
    let initialWindowFrame = window.frame
    let nativeButtons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
        .compactMap { window.standardWindowButton($0) }
    let initialButtons = nativeButtons.map { view.convert($0.bounds, from: $0) }
    for language in Array(repeating: AppLanguage.allCases, count: 5).flatMap({ $0 }) {
        for size in InterfaceSize.allCases {
            settings.updatePreferences {
                $0.language = language
                $0.interfaceSize = size
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            let visible = NSScreen.main?.visibleFrame.size ?? NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            let expected = NSSize(width: min(618, visible.width),
                                  height: min(654, visible.height))
            guard abs(window.frame.width - expected.width) <= 1,
                  abs(window.frame.height - expected.height) <= 1 else {
                fatalError("\(language.rawValue) \(size.rawValue): actual=\(window.frame.size) expected=\(expected)")
            }
            assert(abs(view.bounds.width - expected.width) <= 1)
            assert(abs(view.bounds.height - expected.height) <= 1)
            assert(window.frame == initialWindowFrame)
            assert(nativeButtons.map { view.convert($0.bounds, from: $0) } == initialButtons)
            for child in view.subviews where child is SettingsSidebarMaterialView {
                assert(abs(child.frame.height - expected.height) <= 1)
            }
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let name = "\(language.localeIdentifier)-\(Int((size.scale * 100).rounded())).png"
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        }
    }

    for language in AppLanguage.allCases {
        for size in InterfaceSize.allCases {
            settings.updatePreferences { $0.language = language; $0.interfaceSize = size }
            for page in SettingsSection.allCases {
                settings.selectSection(page)
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                view.layoutSubtreeIfNeeded()
                assert(window.frame == initialWindowFrame)
                assert(nativeButtons.map { view.convert($0.bounds, from: $0) } == initialButtons)
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let name = "\(language.localeIdentifier)-\(Int((size.scale * 100).rounded()))-\(page.rawValue).png"
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
            }
        }
    }
    settings.updatePreferences {
        $0.language = .english
        $0.interfaceSize = .defaultSize
    }
    let final = SettingsService(defaults: defaults, loginItem: InterfaceLanguageLogin())
    assert(final.preferences.language == .english)
    assert(final.preferences.interfaceSize == .defaultSize)
    print("PASS: Interface Size and Language persist; six live layout combinations use real window/view frames")
    print("Snapshots: \(output.path)")
}

try runInterfaceLanguageChecks()
