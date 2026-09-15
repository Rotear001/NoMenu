// Run with the production AccessibilityService, MenuBarItem and MenuBarSymbol
// sources in the Swift interpreter. No app bundle or signing changes are needed.
// These checks use an injected trust provider, not the test process's TCC grant.
import Foundation
import Combine

@MainActor
func checkAccessibilityStateLifecycle() {
    func pumpRunLoop(for interval: TimeInterval) {
        let end = Date().addingTimeInterval(interval)
        while Date() < end {
            RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.01)))
        }
    }

    var runtimeTrust = true
    var reads = 0
    let service = AccessibilityService {
        reads += 1
        return runtimeTrust
    }
    defer { service.stopPermissionPolling() }
    assert(service.isTrusted && !service.isPermissionPolling)
    assert(reads == 1, "Initial state must come from the runtime provider")

    var transitions: [String] = []
    service.onTrustChange = { [weak service] previous, current in
        guard let service else { fatalError("Service unexpectedly released") }
        assert(service.isTrusted == current)
        assert(service.isPermissionPolling == !current,
               "Timer must already match trust before pipeline/UI callbacks")
        transitions.append("\(previous)->\(current)")
    }
    var publishedStates: [Bool] = []
    let observation = service.$isTrusted.dropFirst().sink { publishedStates.append($0) }
    defer { observation.cancel() }

    for reason in ["application startup", "application became active", "Settings requested"] {
        let before = reads
        assert(service.refreshAccessibilityState(reason: reason))
        assert(reads == before + 1, "Each explicit check must read current trust")
        assert(!service.isPermissionPolling)
    }
    assert(transitions.isEmpty && publishedStates.isEmpty)
    print("PASS: already granted, fresh explicit checks, no redundant publication or polling")

    runtimeTrust = false
    assert(!service.refreshAccessibilityState(reason: "Settings requested"))
    assert(!service.isTrusted && service.isPermissionPolling)
    for _ in 0..<20 {
        service.beginPermissionPollingIfNeeded()
        assert(!service.refreshAccessibilityState(reason: "repeated permission presentation"))
    }
    assert(transitions == ["true->false"])
    let beforeFalsePoll = reads
    pumpRunLoop(for: 0.9)
    assert(reads == beforeFalsePoll + 1, "Repeated requests must retain one 750 ms timer")
    assert(service.isPermissionPolling)
    runtimeTrust = true
    let beforeGrant = reads
    pumpRunLoop(for: 0.9)
    assert(service.isTrusted && !service.isPermissionPolling)
    assert(reads == beforeGrant + 1)
    let afterGrant = reads
    pumpRunLoop(for: 0.9)
    assert(reads == afterGrant, "No permission polling may survive a true result")
    print("PASS: one temporary timer, automatic false -> true, timer fully stops")

    runtimeTrust = false
    assert(!service.refreshAccessibilityState(reason: "Settings requested"))
    runtimeTrust = true
    assert(service.refreshAccessibilityState(reason: "application became active"))
    assert(!service.isPermissionPolling, "Activation must not wait for the next tick")
    let afterActivation = reads
    pumpRunLoop(for: 0.9)
    assert(reads == afterActivation, "No queued stale poll after activation")
    assert(publishedStates == [false, true, false, true])
    assert(transitions == ["true->false", "false->true", "true->false", "false->true"])
    print("PASS: revocation/regrant on explicit checks, immediate activation refresh")

    runtimeTrust = false
    assert(!service.refreshAccessibilityState(reason: "Settings requested"))
    let beforeDiscovery = reads
    assert(service.discoverMenuBarItems().items.isEmpty)
    assert(reads == beforeDiscovery + 1, "Discovery must check runtime trust before AX calls")
    service.stopPermissionPolling()
    service.stopPermissionPolling()
    pumpRunLoop(for: 0.9)
    assert(reads == beforeDiscovery + 1 && !service.isPermissionPolling)
    print("PASS: discovery permission gate, idempotent shutdown, no late timer reads")

    let initiallyDenied = AccessibilityService(trustProvider: { false })
    assert(!initiallyDenied.refreshAccessibilityState(reason: "application startup"))
    assert(initiallyDenied.isPermissionPolling,
           "An unchanged false startup result still needs a temporary timer")
    initiallyDenied.stopPermissionPolling()
    print("PASS: initially denied launch begins polling without needing a transition")
}

MainActor.assumeIsolated {
    checkAccessibilityStateLifecycle()
}
