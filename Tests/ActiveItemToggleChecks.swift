// Interpreted alongside production sources (excluding NoMenuApp.swift).
// Exercises synchronous same-item toggle-off and existing switch/outside paths.
import AppKit
import ServiceManagement

final class ActiveToggleDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
}

@MainActor
final class ActiveToggleLogin: LoginItemControlling {
    var status: SMAppService.Status = .notRegistered
    func register() throws { status = .enabled }
    func unregister() throws { status = .notRegistered }
    func openSystemSettings() {}
}

@MainActor
func runActiveItemToggleChecks() {
    let accessibility = AccessibilityService(trustProvider: { true })
    let settings = SettingsService(defaults: ActiveToggleDefaults(), loginItem: ActiveToggleLogin())
    let service = MenuBarService(accessibility: accessibility, settings: settings)
    func item(_ name: String) -> MenuBarItem {
        MenuBarItem(name: name, bundleIdentifier: "test.\(name)", applicationName: name,
                    type: .application, symbolName: "app", processIdentifier: 0,
                    isActionable: true, isAppleProvided: false,
                    accessibilityFrame: nil, visibilityState: .overflowed)
    }
    let first = item("First")
    let second = item("Second")

    // Same active item: one toggle-off clears the authoritative selection now.
    _ = service.beginInteraction(for: first)
    assert(service.selectedItem?.id == first.id)
    assert(service.toggleOffInteractionIfActive(for: first))
    assert(service.selectedItem == nil)
    assert(!service.toggleOffInteractionIfActive(for: first))

    // Repeated clicks alternate open / fully closed without a cleanup click.
    for _ in 0..<5 {
        _ = service.beginInteraction(for: first)
        assert(service.selectedItem?.id == first.id)
        assert(service.toggleOffInteractionIfActive(for: first))
        assert(service.selectedItem == nil)
    }

    // Existing direct switching still transfers ownership in one step.
    _ = service.beginInteraction(for: first)
    _ = service.beginInteraction(for: second)
    assert(service.selectedItem?.id == second.id)

    // Outside/panel dismissal uses the same complete transient-state cleanup.
    service.cancelInteraction()
    assert(service.selectedItem == nil)
    assert(!service.isExternalInteractionPolling)
    print("PASS: same-item toggle-off, repeated toggles, direct switching and outside cleanup converge synchronously")
}

MainActor.assumeIsolated { runActiveItemToggleChecks() }
