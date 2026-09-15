import AppKit

MainActor.assumeIsolated {
    guard let screen = NSScreen.main else { fatalError("Test requires a display") }
    let display = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
    let bounds = CGDisplayBounds(display)
    let strip = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 40)
    let frame = CGRect(x: bounds.maxX - 80, y: bounds.minY, width: 20, height: 20)
    func item(_ name: String, _ pid: pid_t, _ rect: CGRect) -> MenuBarItem {
        MenuBarItem(name: name, bundleIdentifier: "test.\(name)", applicationName: name,
                    type: .application, symbolName: "circle", processIdentifier: pid,
                    isActionable: true, isAppleProvided: false, accessibilityFrame: rect,
                    visibilityState: .overflowed)
    }
    let animated = item("Animated", 1001, frame)
    let other = item("Other", 1002, frame.offsetBy(dx: -30, dy: 0))
    let evidence: [[String: Any]] = [[kCGWindowOwnerPID as String: NSNumber(value: 1001),
        kCGWindowIsOnscreen as String: true, kCGWindowAlpha as String: NSNumber(value: 1),
        kCGWindowBounds as String: frame.dictionaryRepresentation]]
    let first = ArtworkSourceMapping.sources(for: [animated, other], strip: strip, screen: screen, windows: evidence)
    let reversed = ArtworkSourceMapping.sources(for: [other, animated], strip: strip, screen: screen, windows: evidence)
    assert(first == reversed && first == [animated.id: frame])
    assert(ArtworkSourceMapping.sources(for: [other], strip: strip, screen: screen, windows: evidence).isEmpty)
    assert(ArtworkSourceMapping.sources(for: [animated], strip: strip, screen: screen, windows: []).isEmpty)
    let offscreen = item("Offscreen", 1001, frame.offsetBy(dx: bounds.width, dy: 0))
    assert(ArtworkSourceMapping.sources(for: [offscreen], strip: strip, screen: screen, windows: evidence).isEmpty)
    print("PASS: consumer-ID mapping, reorder isolation, owner match, no unused-source capture, no offscreen guessing")

    let store = LiveArtworkImage()
    assert(store.lastCaptureTimestamp == nil && store.lastPublicationTimestamp == nil)
    let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let image = context.makeImage()!
    store.accept(image)
    let publication = store.lastPublicationTimestamp
    store.accept(image)
    assert(store.lastCaptureTimestamp != nil && store.lastPublicationTimestamp == publication)
    assert(store.image != nil)
    print("PASS: cached frame retained, capture/publication timestamps separated; same frame not republished")
}
