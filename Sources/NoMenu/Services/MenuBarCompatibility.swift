import Foundation
import CoreGraphics

/// Only discovery and visibility use this boundary. Interaction remains OS agnostic.
enum MenuBarCompatibility: String {
    case legacy
    case macOS27

    static var current: Self {
        if #available(macOS 27.0, *) { return .macOS27 }
        return .legacy
    }

    static func validatesFullWidthMenuBar(
        window: CGRect, layer: Int, nativeOwner: Bool,
        screen: CGRect, menuBar: CGRect, extras: CGRect
    ) -> Bool {
        // A full-width environment is not an individual item's compositor slot.
        layer == 24 && nativeOwner && window.width > 400 &&
        abs(window.minX - screen.minX) <= 2 && abs(window.width - screen.width) <= 2 &&
        abs(window.minY - screen.minY) <= 2 &&
        window.height >= 12 && window.height <= min(40, menuBar.height + 4) &&
        abs(extras.minY - window.minY) <= 2 && abs(extras.height - window.height) <= 2 &&
        window.insetBy(dx: -2, dy: -2).contains(extras)
    }

    static func isOverflowBoundary(button: CGRect, extras: CGRect) -> Bool {
        // The actionless direct AXButton at the native extras bar's leading edge.
        // Do not depend on its localized Show/Hide description or click it.
        abs(button.minX - extras.minX) <= 2 && abs(button.minY - extras.minY) <= 2 &&
        button.width >= 8 && button.width <= 24 &&
        button.height >= extras.height - 4 && button.height <= extras.height &&
        abs(button.maxY - extras.maxY) <= 2
    }

    static func belongsToNativeOverflow(frame: CGRect, boundary: CGRect) -> Bool {
        // Collapsed items clamp against this boundary; expanded ones move left.
        // Both belong to the same native overflow set that NoMenu should present.
        frame.minX < boundary.maxX + 2
    }
}
