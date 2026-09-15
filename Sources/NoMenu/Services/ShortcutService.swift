import AppKit
import Carbon
import SwiftUI

@MainActor
final class ShortcutService {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var shortcut: NoMenuShortcut?
    private let hotKeyIdentifier = UInt32.random(in: 1...UInt32.max)
    var onPress: (() -> Void)?
    var registrationCount: Int { (hotKey == nil ? 0 : 1) + (handler == nil ? 0 : 1) }

    func register(_ value: NoMenuShortcut?) throws {
        if shortcut == value { return }
        guard let value else {
            stop()
            return
        }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                var key = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &key) == noErr,
                      key.signature == 0x4E4D4E55 else { return OSStatus(eventNotHandledErr) }
                return MainActor.assumeIsolated {
                    let owner = Unmanaged<ShortcutService>.fromOpaque(context).takeUnretainedValue()
                    guard key.id == owner.hotKeyIdentifier else { return OSStatus(eventNotHandledErr) }
                    owner.onPress?()
                    return noErr
                }
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw RegistrationError(status: status) }
        }
        // Register the replacement first. A conflict must leave the old key live.
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(value.keyCode, value.modifiers,
                                        EventHotKeyID(signature: 0x4E4D4E55, id: hotKeyIdentifier),
                                        GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &replacement)
        guard status == noErr else {
            if hotKey == nil { stop() }
            throw RegistrationError(status: status)
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        shortcut = value
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        shortcut = nil
    }

    struct RegistrationError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "\(L10n.text("This shortcut could not be registered.")) (\(status)) \(L10n.text("It may already be in use. Choose another combination."))"
        }
    }
}

struct SettingsShortcutRecorder: NSViewRepresentable {
    @ObservedObject var settings: SettingsService
    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.font = NSFont(name: "Helvetica Neue", size: 11)
        button.appearance = NSAppearance(named: .darkAqua)
        button.target = button
        button.action = #selector(ShortcutRecorderButton.beginRecording)
        button.setAccessibilityLabel(L10n.text("Keyboard Shortcut"))
        return button
    }
    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.language = settings.preferences.language
        button.font = NSFont(name: "Helvetica Neue", size: 11 * settings.preferences.interfaceSize.scale)
        button.setAccessibilityLabel(settings.localized("Keyboard Shortcut"))
        button.valueLabel = settings.preferences.shortcut?.label ?? settings.localized("Record…")
        button.onRecord = { settings.setShortcut($0) }
        button.onError = { settings.shortcutError = $0 }
        button.onRecordingChanged = { settings.shortcutRecordingChanged?($0) }
        if !button.recording { button.title = button.valueLabel }
    }
}

final class ShortcutRecorderButton: NSButton {
    var language: AppLanguage = .systemDefault
    var valueLabel = "Record…"
    var onRecord: ((NoMenuShortcut?) -> Void)?
    var onError: ((String) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() {
        onRecordingChanged?(true)
        recording = true
        title = L10n.text("Press shortcut…", language: language)
        window?.makeFirstResponder(self)
    }
    override func resignFirstResponder() -> Bool {
        if recording { onRecordingChanged?(false) }
        recording = false
        title = valueLabel
        return super.resignFirstResponder()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        if event.keyCode == 51 || event.keyCode == 117 {
            onRecord?(nil)
            finish()
            return
        }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags.contains(.command) || flags.contains(.control),
              let key = event.charactersIgnoringModifiers, !key.isEmpty else {
            onError?(L10n.text("Include Command or Control. Escape cancels; Delete clears the shortcut.", language: language))
            return
        }
        // Preserve native app menu shortcuts; global conflicts are checked by Carbon.
        if conflicts(in: NSApp.mainMenu, key: key, flags: flags) {
            onError?(L10n.text("This shortcut is already used by a NoMenu menu command.", language: language))
            return
        }
        var modifiers: UInt32 = 0
        var label = ""
        for (flag, carbon, symbol) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"),
                                      (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"),
                                      (.command, cmdKey, "⌘")] where flags.contains(flag) {
            modifiers |= UInt32(carbon)
            label += symbol
        }
        label += key == " " ? "Space" : key.uppercased()
        onRecord?(NoMenuShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label))
        finish()
    }
    private func finish() {
        recording = false
        title = valueLabel
        onRecordingChanged?(false)
        window?.makeFirstResponder(nil)
    }
    private func conflicts(in menu: NSMenu?, key: String, flags: NSEvent.ModifierFlags) -> Bool {
        menu?.items.contains {
            (!$0.keyEquivalent.isEmpty && $0.keyEquivalent.lowercased() == key.lowercased()
             && $0.keyEquivalentModifierMask.intersection([.command, .control, .option, .shift]) == flags)
            || conflicts(in: $0.submenu, key: key, flags: flags)
        } ?? false
    }
}
