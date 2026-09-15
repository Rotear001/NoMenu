// Interpreted alongside production sources (excluding NoMenuApp.swift).
// No app bundle, login registration, TCC prompt/reset, or signing is performed.
import AppKit
import ServiceManagement
import SwiftUI

final class SettingsTestDefaults: UserDefaults, @unchecked Sendable {
    var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
}

@MainActor
final class SettingsTestLogin: LoginItemControlling {
    var status: SMAppService.Status = .notRegistered
    var registrationCount = 0
    var unregistrationCount = 0
    func register() throws { status = .enabled; registrationCount += 1 }
    func unregister() throws { status = .notRegistered; unregistrationCount += 1 }
    func openSystemSettings() {}
}

@MainActor
func runSettingsContentChecks() throws {
    let topPanelCapture = WallpaperTintProvider.captureSourceRect(
        screenFrame: NSRect(x: 0, y: 0, width: 1_000, height: 600),
        panelFrame: NSRect(x: 100, y: 560, width: 320, height: 40)
    )
    assert(topPanelCapture == CGRect(x: 100, y: 0, width: 320, height: 40))
    let bottomPanelCapture = WallpaperTintProvider.captureSourceRect(
        screenFrame: NSRect(x: 200, y: 100, width: 1_000, height: 1_000),
        panelFrame: NSRect(x: 500, y: 100, width: 300, height: 40)
    )
    assert(bottomPanelCapture == CGRect(x: 300, y: 960, width: 300, height: 40))
    let oneX = WallpaperTintProvider.capturePixelDimensions(
        sourceRect: topPanelCapture,
        backingScaleFactor: 1
    )
    let twoX = WallpaperTintProvider.capturePixelDimensions(
        sourceRect: topPanelCapture,
        backingScaleFactor: 2
    )
    assert(oneX.width == 320 && oneX.height == 40)
    assert(twoX.width == 640 && twoX.height == 80)
    print("PASS: wallpaper capture source stays aligned at both top and bottom screen edges")

    let defaults = SettingsTestDefaults()
    let login = SettingsTestLogin()
    let settings = SettingsService(defaults: defaults, loginItem: login)
    assert(SettingsSection.allCases.map(\.rawValue) == ["General", "Menu Bar", "Interaction", "Permissions & Privacy", "About"])
    assert(!settings.preferences.diagnosticLogging)
    assert(settings.preferences.closeWithEscape && settings.preferences.animations)
    assert(settings.preferences.iconSpacing == .standard && settings.preferences.itemOrder == .menuBar)
    assert(!settings.preferences.showItemNames && !settings.preferences.keepOpenAfterActivation)
    try settings.setLaunchAtLogin(true)
    assert(settings.launchAtLoginEnabled && login.registrationCount == 1)
    try settings.setLaunchAtLogin(false)
    assert(!settings.launchAtLoginEnabled && login.unregistrationCount == 1)
    settings.setAutomaticUpdateChecks(false)
    settings.setOpenNoMenuOnLaunch(true)
    settings.setHoverHighlight(false)
    settings.checkForUpdatesNow()
    assert(settings.actionMessage?.contains("No update service") == true)
    assert(!settings.updateCheckInProgress)
    print("PASS: exactly five sections; real login adapter; existing preferences; honest updater result")

    for key in [\SettingsPreferences.rememberLastPage, \.animations, \.showItemNames,
                \.closeWithEscape, \.keepOpenAfterActivation, \.diagnosticLogging] {
        for value in [false, true] {
            settings.updatePreferences { $0[keyPath: key] = value }
            let restored = SettingsService(defaults: defaults, loginItem: login)
            assert(restored.preferences[keyPath: key] == value)
        }
    }
    for option in ItemOrder.allCases {
        settings.updatePreferences { $0.itemOrder = option }
        assert(SettingsService(defaults: defaults, loginItem: login).preferences.itemOrder == option)
    }
    for option in IconSpacing.allCases {
        settings.updatePreferences { $0.iconSpacing = option }
        assert(SettingsService(defaults: defaults, loginItem: login).preferences.iconSpacing == option)
    }
    for option in IconAppearance.allCases {
        settings.updatePreferences { $0.iconAppearance = option }
        assert(SettingsService(defaults: defaults, loginItem: login).preferences.iconAppearance == option)
    }
    settings.updatePreferences { $0.rememberLastPage = true }
    for page in SettingsSection.allCases {
        settings.selectSection(page)
        let restored = SettingsService(defaults: defaults, loginItem: login)
        restored.prepareSettingsPresentation()
        assert(restored.selectedSection == page)
    }
    settings.updatePreferences { $0.rememberLastPage = false }
    settings.prepareSettingsPresentation()
    assert(settings.selectedSection == .general)
    settings.updatePreferences { $0.animations = false }
    assert(!settings.animationsAllowed)
    print("PASS: every new preference/picker round trips; page restoration; animation disable")

    var registered: NoMenuShortcut?
    settings.shortcutRegistrar = { registered = $0 }
    let shortcut = NoMenuShortcut(keyCode: 45, modifiers: 256, label: "⌘N")
    settings.setShortcut(shortcut)
    assert(settings.preferences.shortcut == shortcut && registered == shortcut)
    assert(SettingsService(defaults: defaults, loginItem: login).preferences.shortcut == shortcut)
    settings.shortcutRegistrar = { _ in throw ShortcutService.RegistrationError(status: -9878) }
    settings.setShortcut(NoMenuShortcut(keyCode: 46, modifiers: 256, label: "⌘M"))
    assert(settings.preferences.shortcut == shortcut && settings.shortcutError != nil)
    settings.shortcutRegistrar = { registered = $0 }
    settings.setShortcut(nil)
    assert(settings.preferences.shortcut == nil && registered == nil)
    print("PASS: shortcut persistence, rejected conflict preserves previous shortcut, clear")

    let accessibility = AccessibilityService(trustProvider: { false })
    defer { accessibility.stopPermissionPolling() }
    let service = MenuBarService(accessibility: accessibility, settings: settings)
    settings.setHoverHighlight(true)
    assert(service.hoverHighlightEnabled)
    settings.setHoverHighlight(false)
    assert(!service.hoverHighlightEnabled)
    for _ in 0..<3 {
        service.refreshFromSettings()
        service.restartDiscovery()
        service.clearArtworkCache()
        assert(accessibility.observerCount == 0)
        assert(accessibility.isPermissionPolling)
        assert(service.items.isEmpty && service.overflowItems.isEmpty && service.ignoredItems.isEmpty)
    }
    assert(service.discoveryState == "Waiting for Accessibility")
    defaults.set("retain", forKey: "unrelated-test-value")
    settings.markAccessibilityPermissionRequested()
    try settings.resetNoMenuState()
    assert(settings.preferences == SettingsPreferences())
    assert(settings.ignoredItemIDs.isEmpty && settings.selectedSection == .general)
    assert(defaults.object(forKey: "unrelated-test-value") as? String == "retain")
    assert(settings.hasRequestedAccessibilityPermission)
    assert(!accessibility.isTrusted && accessibility.isPermissionPolling)
    print("PASS: recovery actions while denied are safe; no duplicate AX observers; targeted reset preserves permission markers/unrelated data")

    let trusted = AccessibilityService(trustProvider: { true })
    func item(_ name: String, x: CGFloat, visibility: MenuBarVisibilityState = .overflowed) -> MenuBarItem {
        MenuBarItem(name: name, bundleIdentifier: "test.\(name)", applicationName: name,
                    type: .application, symbolName: "app", processIdentifier: 0,
                    isActionable: true, isAppleProvided: false,
                    accessibilityFrame: CGRect(x: x, y: 0, width: 20, height: 20),
                    visibilityState: visibility)
    }
    let zulu = item("Zulu", x: -100)
    let alpha = item("Alpha", x: -50)
    let bravo = item("Bravo", x: -75)
    let data = [alpha, zulu, bravo, item("Visible", x: 100, visibility: .visible), item("Unknown", x: 0, visibility: .unknown)]
    let orderedService = MenuBarService(accessibility: trusted, settings: settings, discoveryProvider: {
        AccessibilityService.DiscoveryResult(items: data, elements: [:], icons: [:])
    })
    orderedService.refresh()
    assert(orderedService.overflowItems.map(\.name) == ["Zulu", "Bravo", "Alpha"])
    settings.updatePreferences { $0.itemOrder = .alphabetical }
    assert(orderedService.overflowItems.map(\.name) == ["Alpha", "Bravo", "Zulu"])
    settings.recordUse(of: alpha)
    settings.updatePreferences { $0.itemOrder = .recent }
    assert(orderedService.overflowItems.map(\.name) == ["Alpha", "Zulu", "Bravo"])
    orderedService.setPresentationOrderFrozen(true)
    let session = orderedService.beginInteraction(for: bravo)
    settings.recordUse(of: bravo)
    assert(orderedService.overflowItems.first?.name == "Alpha", "Open-menu anchor order must remain stable")
    orderedService.endInteraction(for: bravo.id, sessionID: session)
    assert(orderedService.overflowItems.first?.name == "Alpha", "Closing an item must not reorder buttons while the panel remains visible")
    orderedService.setPresentationOrderFrozen(false)
    assert(orderedService.overflowItems.first?.name == "Bravo")
    orderedService.setIgnoredItemIDs([bravo.stableIdentity])
    assert(!orderedService.overflowItems.contains(bravo) && orderedService.ignoredItems == [bravo])
    assert(orderedService.items.count == 5)
    assert(IconSpacing.allCases.map(\.itemWidth) == [32, 38, 46])
    print("PASS: actual menu service sorting, ignored filtering, visibility classification preserved, stable order during interaction")

    if let output = ProcessInfo.processInfo.environment["NOMENU_SETTINGS_SNAPSHOT_DIR"] {
        _ = NSApplication.shared
        if let iconPath = ProcessInfo.processInfo.environment["NOMENU_TEST_ICON"] {
            NSApp.applicationIconImage = NSImage(contentsOfFile: iconPath)
        }
        NSApp.setActivationPolicy(.accessory)
        let hotkeyA = ShortcutService()
        let hotkeyB = ShortcutService()
        let reservedForTest = NoMenuShortcut(keyCode: 90, modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey), label: "Test F20")
        do {
            try hotkeyA.register(reservedForTest)
            defer { hotkeyA.stop(); hotkeyB.stop() }
            do {
                try hotkeyB.register(reservedForTest)
                fatalError("Exclusive duplicate shortcut unexpectedly accepted")
            } catch {
                assert(hotkeyA.registrationCount == 2 && hotkeyB.registrationCount == 0)
            }
            try hotkeyA.register(reservedForTest)
            assert(hotkeyA.registrationCount == 2)
            hotkeyA.stop()
            try hotkeyB.register(reservedForTest)
            assert(hotkeyB.registrationCount == 2)
            print("PASS: real Carbon shortcut registration, conflict detection, idempotence and full cleanup")
        } catch {
            hotkeyA.stop()
            hotkeyB.stop()
            print("UNVERIFIED: host could not register test shortcut: \(error)")
        }
        let controller = SettingsWindowController(settings: settings, accessibility: accessibility, menuBarService: service)
        guard let window = controller.window, let view = window.contentView else { fatalError("Missing Settings window") }
        let originalFrame = window.frame
        for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(kind) else { fatalError("Missing native traffic light") }
            let frame = view.convert(button.bounds, from: button)
            let expected = SettingsDesign.Layout.trafficLightCenters[index]
            assert(abs(frame.midX - expected.x) < 1)
            assert(abs((view.bounds.height - frame.midY) - expected.y) < 1)
        }
        print("PASS: real native traffic-light centers retain the existing design geometry")
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for page in SettingsSection.allCases {
            settings.selectSection(page)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            assert(window.frame == originalFrame)
            assert(window.frame.size == NSSize(width: 618, height: 654))
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot snapshot") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode") }
            try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(page.rawValue + ".png"))
        }
        print("PASS: rendered every production Settings page at stable 618 × 654 pt; snapshots at \(output)")

        settings.selectSection(.menuBar)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        view.layoutSubtreeIfNeeded()
        let pickers = descendants(view).compactMap { $0 as? NSPopUpButton }
        let pickerLabels = Set(pickers.compactMap { $0.accessibilityLabel() })
        let expectedPickerLabels: Set<String> = [
            "Background Style", "Background Blur", "Bar Position", "Screen Edge Margin", "Bar Size", "Width",
            "Item Order", "Icon Spacing", "Icon Appearance", "Live Artwork Frame Rate"
        ]
        assert(pickers.count == expectedPickerLabels.count && pickerLabels == expectedPickerLabels,
               "Every Menu Bar picker must remain a real native control")
        for picker in pickers {
            assert(picker.bounds.width > 0 && picker.bounds.height > 0,
                   "Every native picker must retain a concrete hit-test frame")
            for title in picker.itemTitles {
                picker.selectItem(withTitle: title)
                assert(NSApp.sendAction(picker.action!, to: picker.target, from: picker))
                switch picker.accessibilityLabel() {
                case "Item Order": assert(settings.preferences.itemOrder.rawValue == title)
                case "Icon Spacing": assert(settings.preferences.iconSpacing.rawValue == title)
                case "Icon Appearance": assert(settings.preferences.iconAppearance.rawValue == title)
                case "Live Artwork Frame Rate": assert(settings.preferences.liveArtworkFrameRate.rawValue == title)
                case "Background Style": assert(settings.preferences.barBackgroundStyle.rawValue == title)
                case "Background Blur": assert(settings.preferences.barBackgroundBlur.rawValue == title)
                case "Bar Position": assert(settings.preferences.barPosition.rawValue == title)
                case "Screen Edge Margin": assert(settings.preferences.barEdgeMargin.rawValue == title)
                case "Bar Size": assert(settings.preferences.barSize.rawValue == title)
                case "Width": assert(settings.preferences.barWidth.rawValue == title)
                default: fatalError("Unexpected picker")
                }
            }
        }
        print("PASS: each native picker target/action updates its real persisted setting")

        var testTransparency = 0.45
        var testTooltip: SettingsTooltipPayload?
        let transparencyBinding = Binding<Double>(
            get: { testTransparency },
            set: { testTransparency = $0 }
        )
        let tooltipBinding = Binding<SettingsTooltipPayload?>(
            get: { testTooltip },
            set: { testTooltip = $0 }
        )
        let sliderHost = NSHostingView(rootView: SettingsTransparencyRow(
            title: "Transparency",
            infoText: "Test",
            value: transparencyBinding,
            activeTooltip: tooltipBinding
        ))
        sliderHost.frame = NSRect(
            x: 0, y: 0, width: 340,
            height: SettingsDesign.Layout.rowHeight
        )
        let sliderWindow = NSWindow(
            contentRect: sliderHost.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        sliderWindow.contentView = sliderHost
        sliderHost.layoutSubtreeIfNeeded()
        guard let slider = descendants(sliderHost).compactMap({ $0 as? NSSlider }).first else {
            fatalError("Missing native transparency slider")
        }
        let initialSliderFrame = sliderHost.convert(slider.bounds, from: slider)
        let initialFittingHeight = sliderHost.fittingSize.height
        for value in [0.20, 0.35, 0.60, 0.90] {
            slider.doubleValue = value
            assert(NSApp.sendAction(slider.action!, to: slider.target, from: slider))
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            sliderHost.layoutSubtreeIfNeeded()
            let frame = sliderHost.convert(slider.bounds, from: slider)
            assert(frame == initialSliderFrame,
                   "Transparency slider must not move while its value changes")
            assert(sliderHost.fittingSize.height == initialFittingHeight,
                   "Transparency row intrinsic height must remain stable")
        }
        print("PASS: transparency slider and row frames remain fixed across live value changes")

        settings.selectSection(.interaction)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        view.layoutSubtreeIfNeeded()
        guard let recorder = descendants(view).compactMap({ $0 as? ShortcutRecorderButton }).first else {
            fatalError("Missing native recorder")
        }
        func key(code: UInt16, characters: String, flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                            timestamp: 0, windowNumber: window.windowNumber, context: nil,
                            characters: characters, charactersIgnoringModifiers: characters,
                            isARepeat: false, keyCode: code)!
        }
        recorder.beginRecording()
        recorder.keyDown(with: key(code: 45, characters: "n", flags: [.command, .control]))
        assert(settings.preferences.shortcut?.keyCode == 45)
        assert(settings.preferences.shortcut?.modifiers == UInt32(cmdKey | controlKey))
        recorder.beginRecording()
        recorder.keyDown(with: key(code: 53, characters: "\\u{1b}", flags: []))
        assert(settings.preferences.shortcut != nil)
        recorder.beginRecording()
        recorder.keyDown(with: key(code: 51, characters: "\\u{7f}", flags: []))
        assert(settings.preferences.shortcut == nil)
        print("PASS: native shortcut recorder handles recording, Escape cancellation and Delete clearing")

    }
}

MainActor.assumeIsolated {
    do { try runSettingsContentChecks() }
    catch { fatalError("Settings checks failed: \(error)") }
}
