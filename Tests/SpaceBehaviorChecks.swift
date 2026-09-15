// Interpreted alongside production sources (excluding NoMenuApp.swift).
// Exercises the generation decisions used by the retained AppKit panel.
func runSpaceBehaviorChecks() {
    var context = NoMenuSpacePresentationContext()
    for cycle in 1...10 {
        context.markPresented()
        assert(!context.presentationIsStale(panelVisible: true, sameScreen: true))
        context.activeSpaceDidChange()
        assert(context.presentedGeneration == nil,
               "Cycle \(cycle): old-Space presentation must be invalidated")
        assert(context.presentationIsStale(panelVisible: true, sameScreen: true),
               "Cycle \(cycle): an old visible flag must not count as current")
        context.markPresented()
        assert(!context.presentationIsStale(panelVisible: true, sameScreen: true),
               "Cycle \(cycle): first click must establish a current presentation")
        assert(context.presentationIsStale(panelVisible: false, sameScreen: true))
        assert(context.presentationIsStale(panelVisible: true, sameScreen: false))
        context.clearPresentation()
    }

    print("PASS: 10 Space generations; stale visible/screen state rejected and first-click presentation accepted")
}

runSpaceBehaviorChecks()
