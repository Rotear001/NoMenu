import AppKit
import CoreGraphics
import OSLog

/// Opt-in, observational tracing for a signed development build. No event is
/// suppressed, reposted, or synthesized. Window titles and key events are omitted.
@MainActor
final class MenuBarClickDiagnostics {
    static let shared = MenuBarClickDiagnostics()
    static let isEnabled: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--debug-menu-bar-clicks")
        #else
        false
        #endif
    }()

    private let logger = Logger(subsystem: "com.nomenu.utility", category: "MenuBarClickDebug")
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var cgMouseEventTap: CFMachPort?
    private var cgMouseRunLoopSource: CFRunLoopSource?
    private var stateDescription: (() -> String)?
    private var awaitsFirstPostDisplayChangeClick = false
    var activeMonitorCount: Int {
        (localMonitor == nil ? 0 : 1)
            + (globalMonitor == nil ? 0 : 1)
            + (cgMouseEventTap == nil ? 0 : 1)
    }

    func start(state: @escaping () -> String) {
        guard Self.isEnabled, localMonitor == nil, globalMonitor == nil else { return }
        stateDescription = state
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        ) { event in
            MainActor.assumeIsolated {
                Self.record("local-observer", event: event, consumed: false)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        ) { event in
            MainActor.assumeIsolated {
                Self.record("global-observer", event: event, consumed: false)
            }
        }

        // Observe both halves of the gesture even if native NSMenu tracking
        // unwinds between them. This DEBUG-only tap never suppresses input.
        let mouseMask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        cgMouseEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mouseMask,
            callback: { _, type, event, _ in
                guard type == .leftMouseDown || type == .leftMouseUp else {
                    return Unmanaged.passUnretained(event)
                }
                let cgPoint = event.location
                let timestamp = event.timestamp
                let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
                let clickState = event.getIntegerValueField(.mouseEventClickState)
                let pressure = event.getDoubleValueField(.mouseEventPressure)
                Task { @MainActor in
                    MenuBarClickDiagnostics.record(
                        "cg-session-observer",
                        point: MenuBarClickDiagnostics.appKitPoint(from: cgPoint),
                        consumed: false,
                        detail: "cgType=\(type.rawValue) cgEventTime=\(timestamp) sourcePID=\(sourcePID) clickState=\(clickState) pressure=\(pressure)"
                    )
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        if let cgMouseEventTap {
            let source = CFMachPortCreateRunLoopSource(nil, cgMouseEventTap, 0)
            cgMouseRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: cgMouseEventTap, enable: true)
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let cgMouseRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), cgMouseRunLoopSource, .commonModes)
        }
        if let cgMouseEventTap {
            CGEvent.tapEnable(tap: cgMouseEventTap, enable: false)
            CFMachPortInvalidate(cgMouseEventTap)
        }
        localMonitor = nil
        globalMonitor = nil
        cgMouseRunLoopSource = nil
        cgMouseEventTap = nil
        stateDescription = nil
        awaitsFirstPostDisplayChangeClick = false
    }

    static func markDisplayGeometryInvalidated() {
        guard isEnabled else { return }
        shared.awaitsFirstPostDisplayChangeClick = true
    }

    static func recordFirstPostDisplayChangeClickIfNeeded(
        button: NSButton,
        item: MenuBarItem?,
        event: NSEvent
    ) {
        guard isEnabled, shared.awaitsFirstPostDisplayChangeClick else { return }
        shared.awaitsFirstPostDisplayChangeClick = false
        let point = event.window?.convertPoint(toScreen: event.locationInWindow)
            ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
        let screenID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            .map(String.init(describing:)) ?? "none"
        let buttonFrame: NSRect
        if let window = button.window {
            buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        } else {
            buttonFrame = .zero
        }
        shared.emit(
            "[NoMenuDisplayRegression] first post-change click point=\(point) resolvedScreen=\(screenID) buttonFrame=\(buttonFrame) hitItemID=\(item?.id.uuidString ?? "none") hitStableIdentity=\(item?.stableIdentity ?? "none")"
        )
    }

    private static func appKitPoint(from cgPoint: CGPoint) -> NSPoint {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber else { continue }
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard displayBounds.contains(cgPoint) else { continue }
            return NSPoint(
                x: screen.frame.minX + cgPoint.x - displayBounds.minX,
                y: screen.frame.maxY - (cgPoint.y - displayBounds.minY)
            )
        }
        return NSPoint(x: cgPoint.x, y: cgPoint.y)
    }

    static func record(
        _ stage: String,
        event: NSEvent? = nil,
        point: NSPoint? = nil,
        consumed: Bool? = nil,
        detail: @autoclosure () -> String = ""
    ) {
        guard isEnabled else { return }
        let screenPoint = point ?? event.flatMap { event in
            event.window?.convertPoint(toScreen: event.locationInWindow)
        } ?? NSEvent.mouseLocation
        let windows = NSApp.windows
        let nearMenuBar = NSScreen.screens.contains {
            NSRect(x: $0.frame.minX, y: $0.frame.maxY - 100,
                   width: $0.frame.width, height: 100).contains(screenPoint)
        }
        guard nearMenuBar || windows.contains(where: {
            $0 is NoMenuPanel && $0.isVisible && $0.frame.contains(screenPoint)
        }) else { return }

        // Unlike sorting CGWindowList entries by alpha/level, this AppKit API
        // asks which window would actually receive mouseDown at the given point.
        // At a later handler this is a fresh query, not proof of earlier routing;
        // event.windowNumber below is the delivered local event's actual window.
        let target = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0)
        let targetIsOurs = windows.contains { $0.windowNumber == target }
        let eventInfo = event.map { event in
            let mouseTypes: Set<NSEvent.EventType> = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
            let number = mouseTypes.contains(event.type) ? String(event.eventNumber) : "unavailable"
            return "eventTime=\(event.timestamp) eventType=\(event.type.rawValue) eventNumber=\(number) deliveredWindow=\(event.windowNumber)"
        } ?? "eventTime=unavailable deliveredWindow=unavailable"
        let decision = consumed.map(String.init) ?? "not-a-consumption-decision"
        shared.emit("stage=\(stage) point=\(screenPoint) currentMouse=\(NSEvent.mouseLocation) \(eventInfo) hitWindowNow=\(target) hitWindowIsNoMenu=\(targetIsOurs) consumed=\(decision) state={\(shared.stateDescription?() ?? "unavailable")} \(detail())")

        for window in windows {
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            // NSView.hitTest takes coordinates in the receiver's superview.
            let hit = window.contentView.flatMap { content -> NSView? in
                guard let parent = content.superview else { return nil }
                return content.hitTest(parent.convert(windowPoint, from: nil))
            }
            shared.emit("window=\(window.windowNumber) class=\(type(of: window)) frame=\(window.frame) level=\(window.level.rawValue) visible=\(window.isVisible) alpha=\(window.alphaValue) ignoresMouse=\(window.ignoresMouseEvents) mouseMoved=\(window.acceptsMouseMovedEvents) collection=\(window.collectionBehavior.rawValue) contains=\(window.frame.contains(screenPoint)) hitView=\(hit.map { String(describing: type(of: $0)) } ?? "none")")
        }

        // Compositor candidates describe stacking only; they are not treated as
        // proof that a transparent window is hit-testable. Do not log titles.
        guard let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        let cgPoint = CGPoint(x: screenPoint.x, y: primary.frame.maxY - screenPoint.y)
        for entry in list {
            guard let rawBounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary),
                  bounds.contains(cgPoint) else { continue }
            shared.emit("compositorCandidate id=\(entry[kCGWindowNumber as String] ?? "unknown") pid=\(entry[kCGWindowOwnerPID as String] ?? "unknown") owner=\(entry[kCGWindowOwnerName as String] ?? "unknown") bounds=\(bounds) level=\(entry[kCGWindowLayer as String] ?? "unknown") alpha=\(entry[kCGWindowAlpha as String] ?? "unknown")")
        }
    }

    private func emit(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
