// Hidden production-view layout check; does not change app preferences or TCC.
// Run with Tests/run-settings-checks.swift AboutRenderChecks.swift.
// The interpreter has no app Info.plist, so bundle fields intentionally use
// their unavailable fallbacks. Installed-bundle values are verified separately.
import AppKit
import ServiceManagement

final class AboutTestDefaults: UserDefaults, @unchecked Sendable {
    var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
}

@MainActor
final class AboutTestLogin: LoginItemControlling {
    var status: SMAppService.Status = .notRegistered
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}

@MainActor
func checkAboutRendering() throws {
    _ = NSApplication.shared
    if let iconPath = ProcessInfo.processInfo.environment["NOMENU_TEST_ICON"] {
        NSApp.applicationIconImage = NSImage(contentsOfFile: iconPath)
    }
    let settings = SettingsService(defaults: AboutTestDefaults(), loginItem: AboutTestLogin())
    settings.selectSection(.about)
    let accessibility = AccessibilityService(trustProvider: { false })
    defer { accessibility.stopPermissionPolling() }
    let service = MenuBarService(accessibility: accessibility, settings: settings)
    let controller = SettingsWindowController(settings: settings, accessibility: accessibility, menuBarService: service)
    guard let window = controller.window, let view = window.contentView else { fatalError("Missing view") }
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    assert(window.frame.size == NSSize(width: 618, height: 654))
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let png = bitmap.representation(using: .png, properties: [:])!
    let output = ProcessInfo.processInfo.environment["NOMENU_SETTINGS_SNAPSHOT_DIR"]!
    let path = URL(fileURLWithPath: output).appendingPathComponent("About.png")
    try png.write(to: path)
    print("About layout snapshot (interpreter bundle fallbacks): \(path.path)")
}

try checkAboutRendering()
