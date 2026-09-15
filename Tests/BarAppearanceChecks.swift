import AppKit
import ServiceManagement

final class BarAppearanceDefaults: UserDefaults, @unchecked Sendable {
    var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
}

@MainActor final class BarAppearanceLogin: LoginItemControlling {
    var status: SMAppService.Status = .notRegistered
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}

@MainActor
func runBarAppearanceChecks() {
    let defaults = BarAppearanceDefaults()
    let settings = SettingsService(defaults: defaults, loginItem: BarAppearanceLogin())
    assert(settings.preferences.barBackgroundStyle == .current)
    assert(settings.preferences.barTransparency == 0.50)
    assert(settings.preferences.barBackgroundBlur == .medium)
    assert(settings.preferences.barPosition == .right)
    assert(settings.preferences.barSize == .standard)
    assert(settings.preferences.barWidth == .fitContent)

    settings.updatePreferences {
        $0.barBackgroundStyle = .wallpaper
        $0.barTransparency = 0.90
        $0.barBackgroundBlur = .high
        $0.barPosition = .center
        $0.barEdgeMargin = .spacious
        $0.barSize = .large
        $0.barWidth = .wide
    }
    let restored = SettingsService(defaults: defaults, loginItem: BarAppearanceLogin())
    assert(restored.preferences.barBackgroundStyle == .wallpaper)
    assert(restored.preferences.barTransparency == 0.90)
    assert(restored.preferences.barBackgroundBlur == .high)
    assert(restored.preferences.barPosition == .center)
    assert(restored.preferences.barEdgeMargin == .spacious)
    assert(restored.preferences.barSize == .large)
    assert(restored.preferences.barWidth == .wide)
    settings.updatePreferences { $0.interfaceSize = .extraLarge }
    assert(settings.preferences.barSize == .large)
    settings.updatePreferences { $0.barSize = .compact }
    assert(settings.preferences.interfaceSize == .extraLarge)
    settings.updatePreferences { $0.barTransparency = 0.0 }
    assert(settings.preferences.barTransparency == 0.20)
    settings.updatePreferences { $0.barTransparency = 1.0 }
    assert(settings.preferences.barTransparency == 0.90)

    let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
    let visible = NSRect(x: 0, y: 0, width: 1512, height: 947)
    let safe = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    var preferences = SettingsPreferences()
    let original = NoMenuBarLayout.resolve(screenFrame: screen, visibleFrame: visible,
                                            safeAreaInsets: safe, itemCount: 4,
                                            preferences: preferences)
    for _ in 0..<5 {
        for background in NoMenuBackgroundStyle.allCases {
            for position in NoMenuBarPosition.allCases {
                for size in NoMenuBarSize.allCases {
                    for width in NoMenuBarWidth.allCases {
                        preferences.barBackgroundStyle = background
                        preferences.barPosition = position
                        preferences.barSize = size
                        preferences.barWidth = width
                        let layout = NoMenuBarLayout.resolve(screenFrame: screen, visibleFrame: visible,
                                                              safeAreaInsets: safe, itemCount: 4,
                                                              preferences: preferences)
                        assert(screen.contains(layout.frame))
                        assert(layout.itemHeight <= layout.frame.height)
                    }
                }
            }
        }
    }
    preferences.resetBarAppearanceAndLayout()
    preferences.barWidth = .fitContent
    preferences.barPosition = .left
    let left = NoMenuBarLayout.resolve(screenFrame: screen, visibleFrame: visible,
                                       safeAreaInsets: safe, itemCount: 4, preferences: preferences)
    preferences.barPosition = .center
    let center = NoMenuBarLayout.resolve(screenFrame: screen, visibleFrame: visible,
                                         safeAreaInsets: safe, itemCount: 4, preferences: preferences)
    preferences.barPosition = .right
    let right = NoMenuBarLayout.resolve(screenFrame: screen, visibleFrame: visible,
                                        safeAreaInsets: safe, itemCount: 4, preferences: preferences)
    assert(left.frame.minX < center.frame.minX && center.frame.minX < right.frame.minX)

    let secondaryScreen = NSRect(x: -1280, y: 120, width: 1280, height: 800)
    let secondaryVisible = NSRect(x: -1280, y: 120, width: 1280, height: 776)
    let secondary = NoMenuBarLayout.resolve(
        screenFrame: secondaryScreen, visibleFrame: secondaryVisible,
        safeAreaInsets: NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 22),
        itemCount: 30, preferences: preferences
    )
    assert(secondaryScreen.contains(secondary.frame))

    // A display rotation replaces the screen coordinate space. Re-resolving the
    // same bar against the replacement geometry must never retain the previous
    // landscape origin or produce a frame outside the portrait screen.
    let landscapeScreen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    let landscapeVisible = NSRect(x: 0, y: 0, width: 1920, height: 1055)
    let portraitScreen = NSRect(x: 0, y: 0, width: 1080, height: 1920)
    let portraitVisible = NSRect(x: 0, y: 0, width: 1080, height: 1895)
    let landscape = NoMenuBarLayout.resolve(
        screenFrame: landscapeScreen, visibleFrame: landscapeVisible,
        safeAreaInsets: safe, itemCount: 12, preferences: preferences
    )
    let portrait = NoMenuBarLayout.resolve(
        screenFrame: portraitScreen, visibleFrame: portraitVisible,
        safeAreaInsets: safe, itemCount: 12, preferences: preferences
    )
    assert(landscapeScreen.contains(landscape.frame))
    assert(portraitScreen.contains(portrait.frame))
    assert(landscape.frame != portrait.frame)
    preferences.resetBarAppearanceAndLayout()
    let reset = NoMenuBarLayout.resolve(screenFrame: screen, visibleFrame: visible,
                                         safeAreaInsets: safe, itemCount: 4,
                                         preferences: preferences)
    assert(reset == original)
    settings.resetBarAppearanceAndLayout()
    assert(settings.preferences.barBackgroundStyle == .current)
    assert(settings.preferences.barTransparency == 0.50)
    assert(settings.preferences.barBackgroundBlur == .medium)
    assert(settings.preferences.barPosition == .right)
    assert(settings.preferences.barSize == .standard)
    assert(settings.preferences.barWidth == .fitContent)
    print("PASS: NoMenu bar appearance persistence, screen-relative geometry, and exact reset")
}

runBarAppearanceChecks()
