// Interpreted alongside production sources (excluding NoMenuApp.swift).
// Ensures a global mouse-down has one deterministic owner before actions run.
import AppKit

func runOutsideDismissalChecks() {
    let status = NSRect(x: 900, y: 900, width: 34, height: 24)
    let panel = NSRect(x: 700, y: 820, width: 200, height: 36)

    assert(NoMenuGlobalMouseDownClassification.classify(
        point: NSPoint(x: 910, y: 910),
        statusItemFrame: status,
        panelFrame: panel,
        preservesExternalInteraction: true
    ) == .statusItem)
    assert(NoMenuGlobalMouseDownClassification.classify(
        point: NSPoint(x: 720, y: 830),
        statusItemFrame: status,
        panelFrame: panel,
        preservesExternalInteraction: true
    ) == .panel)
    assert(NoMenuGlobalMouseDownClassification.classify(
        point: NSPoint(x: 500, y: 500),
        statusItemFrame: status,
        panelFrame: panel,
        preservesExternalInteraction: true
    ) == .externalInteraction)
    assert(NoMenuGlobalMouseDownClassification.classify(
        point: NSPoint(x: 500, y: 500),
        statusItemFrame: status,
        panelFrame: panel,
        preservesExternalInteraction: false
    ) == .outside)
    print("PASS: one authoritative global mouse-down classification; outside is never promoted by proximity")
}

runOutsideDismissalChecks()
