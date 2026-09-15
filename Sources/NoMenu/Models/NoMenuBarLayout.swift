import AppKit

struct NoMenuBarLayout: Equatable {
    let frame: NSRect
    let itemWidth: CGFloat
    let iconSize: CGFloat
    let itemHeight: CGFloat
    let horizontalPadding: CGFloat

    static func resolve(
        screen: NSScreen,
        itemCount: Int,
        preferences: SettingsPreferences
    ) -> NoMenuBarLayout {
        resolve(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            itemCount: itemCount,
            preferences: preferences
        )
    }

    static func resolve(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        safeAreaInsets safe: NSEdgeInsets,
        itemCount: Int,
        preferences: SettingsPreferences
    ) -> NoMenuBarLayout {
        let size = preferences.barSize
        let usableMinX = max(visibleFrame.minX, screenFrame.minX + safe.left)
        let usableMaxX = min(visibleFrame.maxX, screenFrame.maxX - safe.right)
        let usableWidth = max(1, usableMaxX - usableMinX)
        let margin = min(preferences.barEdgeMargin.points, usableWidth / 4)
        let maximumWidth = max(1, usableWidth - margin * 2)
        let itemWidth = max(24, preferences.iconSpacing.itemWidth + size.itemWidthAdjustment)
        let naturalWidth = max(72, size.horizontalPadding * 2 + CGFloat(max(1, itemCount)) * itemWidth)
        let desiredWidth: CGFloat
        switch preferences.barWidth {
        case .fitContent:
            desiredWidth = naturalWidth
        case .compact:
            desiredWidth = max(naturalWidth, min(320, maximumWidth * 0.42))
        case .wide:
            desiredWidth = max(naturalWidth, maximumWidth * 0.72)
        }
        let width = min(maximumWidth, desiredWidth)
        let x: CGFloat
        switch preferences.barPosition {
        case .left:
            x = usableMinX + margin
        case .center:
            x = usableMinX + (usableWidth - width) / 2
        case .right:
            x = usableMaxX - margin - width
        }
        let menuBarHeight = max(24, screenFrame.maxY - visibleFrame.maxY)
        let y = screenFrame.maxY - menuBarHeight - 4 - size.height
        return NoMenuBarLayout(
            frame: NSRect(x: min(max(x, usableMinX), usableMaxX - width), y: y,
                          width: width, height: size.height),
            itemWidth: itemWidth,
            iconSize: size.iconSize,
            itemHeight: size.itemHeight,
            horizontalPadding: size.horizontalPadding
        )
    }
}
