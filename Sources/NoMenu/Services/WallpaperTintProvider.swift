import AppKit
import Combine
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Supplies the actual wallpaper pixels directly behind the retained NoMenu
/// panel. The one-shot capture excludes every on-screen window, leaving the
/// compositor's desktop background; it never reads another app's wallpaper file
/// and never reduces the result to a flat average color.
@MainActor
final class WallpaperTintProvider: ObservableObject {
    static let shared = WallpaperTintProvider()

    private struct WallpaperSource: Equatable {
        let displayID: CGDirectDisplayID
        let screenFrame: NSRect
        let panelFrame: NSRect
        let backingScaleFactor: CGFloat
    }

    @Published private(set) var panelImage: NSImage?
    private var cachedSources: [CGDirectDisplayID: WallpaperSource] = [:]
    private var cachedImages: [CGDirectDisplayID: NSImage] = [:]
    private var capturedAt: [CGDirectDisplayID: Date] = [:]
    private var pendingSources: [CGDirectDisplayID: WallpaperSource] = [:]
    private var latestRequestedSource: WallpaperSource?

    func refresh(for screen: NSScreen, panelFrame: NSRect) {
        guard !panelFrame.isEmpty,
              CGPreflightScreenCaptureAccess(),
              let displayID = Self.displayID(for: screen) else {
            panelImage = nil
            return
        }
        let source = WallpaperSource(
            displayID: displayID,
            screenFrame: screen.frame,
            panelFrame: panelFrame,
            backingScaleFactor: screen.backingScaleFactor
        )
        // panelImage is shared across displays. A capture for an old display can
        // complete after a newer display request, so publication must follow the
        // latest global geometry rather than merely the per-display pending slot.
        latestRequestedSource = source
        if cachedSources[displayID] == source,
           let cached = cachedImages[displayID],
           Date().timeIntervalSince(capturedAt[displayID] ?? .distantPast) < 1 {
            panelImage = cached
            return
        }
        guard pendingSources[displayID] != source else { return }
        pendingSources[displayID] = source
        Task { [weak self] in
            let image = await Self.captureWallpaper(for: source)
            guard let self, self.pendingSources[displayID] == source else { return }
            self.pendingSources[displayID] = nil
            guard self.latestRequestedSource == source, let image else { return }
            let rendered = NSImage(
                cgImage: image,
                size: NSSize(width: source.panelFrame.width,
                             height: source.panelFrame.height)
            )
            self.cachedSources[displayID] = source
            self.cachedImages[displayID] = rendered
            self.capturedAt[displayID] = Date()
            self.panelImage = rendered
        }
    }

    func invalidateScreenCache() {
        cachedSources.removeAll()
        cachedImages.removeAll()
        capturedAt.removeAll()
        pendingSources.removeAll()
        latestRequestedSource = nil
        // Keep the last complete frame while WindowServer settles. It cannot be
        // republished by an invalidated task, and the next valid crop replaces it
        // atomically instead of flashing an empty or partially updated background.
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber)?.uint32Value
    }

    nonisolated private static func captureWallpaper(
        for source: WallpaperSource
    ) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: {
                $0.displayID == source.displayID
            }) else { return nil }

            // Preserve only windows at the WindowServer desktop/wallpaper
            // levels. macOS and live-wallpaper apps render the current Space's
            // actual background there; excluding those as ordinary windows
            // would produce a black compositor backstop.
            let wallpaperIDs = wallpaperWindowIDs(covering: source.screenFrame)
            let filter = SCContentFilter(
                display: display,
                excludingWindows: content.windows.filter {
                    !wallpaperIDs.contains($0.windowID)
                }
            )
            let config = SCStreamConfiguration()
            let rect = captureSourceRect(
                screenFrame: source.screenFrame,
                panelFrame: source.panelFrame
            )
            let dimensions = capturePixelDimensions(
                sourceRect: rect,
                backingScaleFactor: source.backingScaleFactor
            )
            config.sourceRect = rect
            config.width = dimensions.width
            config.height = dimensions.height
            config.showsCursor = false
            config.capturesAudio = false
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            return nil
        }
    }

    nonisolated private static func wallpaperWindowIDs(
        covering screen: CGRect
    ) -> Set<CGWindowID> {
        guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        return Set(raw.compactMap { window -> CGWindowID? in
            guard let number = window[kCGWindowNumber as String] as? NSNumber,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer >= desktopLevel - 2, layer <= desktopLevel,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary),
                  bounds.contains(CGPoint(x: screen.midX, y: screen.midY)),
                  bounds.width >= screen.width * 0.9,
                  bounds.height >= screen.height * 0.9 else { return nil }
            let owner = window[kCGWindowOwnerName as String] as? String
            guard owner != "Window Server", owner != "loginwindow" else { return nil }
            return number.uint32Value
        })
    }

    /// Converts AppKit's bottom-left screen coordinates to ScreenCaptureKit's
    /// display-local, top-left source rectangle.
    nonisolated static func captureSourceRect(
        screenFrame screen: NSRect,
        panelFrame panel: NSRect
    ) -> CGRect {
        CGRect(
            x: panel.minX - screen.minX,
            y: screen.maxY - panel.maxY,
            width: panel.width,
            height: panel.height
        )
    }

    nonisolated static func capturePixelDimensions(
        sourceRect: CGRect,
        backingScaleFactor: CGFloat
    ) -> (width: Int, height: Int) {
        (
            max(1, Int((sourceRect.width * backingScaleFactor).rounded())),
            max(1, Int((sourceRect.height * backingScaleFactor).rounded()))
        )
    }
}
