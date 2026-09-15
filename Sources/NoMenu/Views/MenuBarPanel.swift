import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var service: MenuBarService
    @ObservedObject var accessibility: AccessibilityService
    @ObservedObject private var wallpaperTint = WallpaperTintProvider.shared

    var body: some View {
        HStack(spacing: 5) {
            Spacer(minLength: metrics.horizontalPadding)

            if !accessibility.isTrusted {
                Button {
                    accessibility.requestPermission()
                } label: {
                    Image(systemName: "accessibility")
                        .font(.system(size: metrics.iconSize, weight: .semibold))
                        .frame(width: metrics.itemWidth, height: metrics.itemHeight)
                }
                .buttonStyle(.plain)
                .help(L10n.text("Allow Accessibility access", language: service.settings.preferences.language))
            } else if !service.overflowItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(service.overflowItems) { item in
                            MenuItemButton(
                                item: item,
                                icon: service.icon(for: item),
                                artwork: service.liveArtwork(for: item.id),
                                isSelected: service.selectedItem?.id == item.id,
                                hoverHighlightEnabled: service.hoverHighlightEnabled,
                                service: service
                            )
                            .frame(width: metrics.itemWidth, height: metrics.itemHeight)
                        }
                    }
                }
            }

            Spacer(minLength: metrics.horizontalPadding)
        }
        .foregroundStyle(.white.opacity(0.96))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                NoMenuBackgroundVisualEffect(
                    blur: service.settings.preferences.barBackgroundStyle == .wallpaper
                        ? .off : service.settings.preferences.barBackgroundBlur
                )
                appearanceBackground
            }
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.055), lineWidth: 0.5)
            }
        }
        .animation(service.settings.animationsAllowed ? .easeInOut(duration: 0.20) : nil,
                   value: service.settings.preferences.barBackgroundStyle)
        .animation(service.settings.animationsAllowed ? .easeInOut(duration: 0.18) : nil,
                   value: service.settings.preferences.barTransparency)
        .preferredColorScheme(.dark)
    }

    private var metrics: NoMenuBarLayout {
        let preferences = service.settings.preferences
        let size = preferences.barSize
        return NoMenuBarLayout(
            frame: .zero,
            itemWidth: max(24, preferences.iconSpacing.itemWidth + size.itemWidthAdjustment),
            iconSize: size.iconSize,
            itemHeight: size.itemHeight,
            horizontalPadding: size.horizontalPadding
        )
    }

    @ViewBuilder private var appearanceBackground: some View {
        let transparency = service.settings.preferences.barTransparency
        switch service.settings.preferences.barBackgroundStyle {
        case .current:
            Color.black.opacity(max(0.04, 0.36 * (1 - transparency)))
        case .wallpaper:
            ZStack {
                if let image = wallpaperTint.panelImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .blur(radius: wallpaperBlurRadius, opaque: true)
                }
                Color.black.opacity(max(0.08, 0.44 * (1 - transparency)))
            }
        case .noMenu:
            Color(red: 18 / 255, green: 19 / 255, blue: 21 / 255)
                .opacity(1 - transparency * 0.65)
        }
    }

    private var wallpaperBlurRadius: CGFloat {
        switch service.settings.preferences.barBackgroundBlur {
        case .off: 0
        case .low: 2
        case .medium: 5
        case .high: 10
        }
    }
}
