import AppKit
import ServiceManagement
import SwiftUI

enum SettingsDesign {
    enum Layout {
        private static var s: CGFloat { InterfaceScaleStore.current }
        static var preferredWindowSize: NSSize { NSSize(width: 618, height: 654) }
        static var windowWidth: CGFloat { InterfaceScaleStore.availableWindowSize?.width ?? preferredWindowSize.width }
        static var windowHeight: CGFloat { InterfaceScaleStore.availableWindowSize?.height ?? preferredWindowSize.height }
        static var windowSize: NSSize { NSSize(width: windowWidth, height: windowHeight) }
        static var outerCornerRadius: CGFloat { 30 }
        static var leftRegionWidth: CGFloat { 207 }

        static var sidebarX: CGFloat { 14.5 }
        static var sidebarY: CGFloat { 11 }
        static var sidebarWidth: CGFloat { 178 }
        static var sidebarHeight: CGFloat { windowHeight - 22 }
        static var sidebarCornerRadius: CGFloat { 18 }
        static var sidebarBorderWidth: CGFloat { 1.5 }

        static var navigationX: CGFloat { 11.5 }
        static var navigationY: CGFloat { 43 }
        static var navigationWidth: CGFloat { 158 }
        static var navigationRowHeight: CGFloat { 30 * s }
        static var navigationRowSpacing: CGFloat { 10 * s }
        static var navigationIconSize: CGFloat { 20 * s }
        static var navigationIconInset: CGFloat { 8 * s }
        static var navigationIconToText: CGFloat { 5 * s }

        static var contentX: CGFloat { 217 }
        static var titleY: CGFloat { 23 }
        static var contentWidth: CGFloat { windowWidth - contentX - 11 }
        static var titleHeight: CGFloat { 25 }
        static var panelY: CGFloat { 59 }
        static var panelHeight: CGFloat { windowHeight - 79 }
        static var panelCornerRadius: CGFloat { 20 }

        static var wideHorizontalPadding: CGFloat { 40 }
        static var compactHorizontalPadding: CGFloat { 30 }
        static var compactRowInset: CGFloat { 10 }
        static var panelTopPadding: CGFloat { 25 }
        static var rowHeight: CGFloat { 35 * s }
        static var rowSpacing: CGFloat { 10 * s }
        static var behaviorHeaderHeight: CGFloat { 24 * s }

        static var toggleWidth: CGFloat { 35 * s }
        static var toggleHeight: CGFloat { 20 * s }
        static var toggleKnobSize: CGFloat { 18 * s }
        static var toggleKnobInset: CGFloat { 1 * s }
        static let toggleAnimationDuration: Double = 0.2
        static var actionWidth: CGFloat { 40 * s }
        static var actionHeight: CGFloat { 20 * s }
        static var actionIconSize: CGFloat { 12 * s }
        static var disclosureIconSize: CGFloat { 9 * s }

        static var disclosureContentHeight: CGFloat { 150 * s }
        static var disclosureVerticalInset: CGFloat { 5 * s }
        static var disclosureExpandedExtent: CGFloat { 160 * s }
        static var disclosureCornerRadius: CGFloat { 29 * s }
        static let disclosureDuration: Double = 0.18

        static let trafficLightCenters: [NSPoint] = [
            NSPoint(x: 36.5, y: 33),
            NSPoint(x: 52.25, y: 33),
            NSPoint(x: 68.25, y: 33)
        ]
        static var headerDragRegionHeight: CGFloat { 49 }

        static var aboutHeaderX: CGFloat { 15 * s }
        static var aboutHeaderY: CGFloat { 34 * s }
        static var aboutHeaderWidth: CGFloat { contentWidth - 30 * s }
        static var aboutHeaderHeight: CGFloat { 130 * s }
        static var aboutIconSize: CGFloat { 90 * s }
    }

    enum Colors {
        static let rightShell = Color(red: 39 / 255, green: 39 / 255, blue: 39 / 255)
        static let leftShellTint = Color(red: 18 / 255, green: 20 / 255, blue: 23 / 255)
            .opacity(0.12)
        static let sidebarTop = Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255)
        static let sidebarBottom = Color(red: 48 / 255, green: 48 / 255, blue: 48 / 255)
        static let sidebarBorder = Color(red: 0.44, green: 0.46, blue: 0.50).opacity(0.28)
        static let sidebarGlow = Color.black.opacity(0.34)
        static let panelTop = Color(red: 57 / 255, green: 57 / 255, blue: 57 / 255)
        static let panelBottom = Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
        static let insetPanel = Color(red: 35 / 255, green: 35 / 255, blue: 35 / 255)
        static let selection = Color(red: 65 / 255, green: 75 / 255, blue: 111 / 255)
        static let control = Color.white.opacity(0.10)
        static let divider = Color.white.opacity(0.42)
        static let primary = Color.white.opacity(0.96)
        static let secondary = Color.white.opacity(0.48)
        static let tertiary = Color.white.opacity(0.36)
        static let toggleBlue = Color(red: 0 / 255, green: 105 / 255, blue: 205 / 255)
    }

    enum Typography {
        // The PDF's Type 3 glyph widths match Helvetica Neue Regular (for
        // example, "General" is 87.1 pt at 25 pt and 52.3 pt at 15 pt).
        private static var s: CGFloat { InterfaceScaleStore.current }
        static var pageTitle: Font { .custom("Helvetica Neue", fixedSize: 25) }
        static var navigation: Font { .custom("Helvetica Neue", fixedSize: 15 * s) }
        static var row: Font { .custom("Helvetica Neue", fixedSize: 12 * s) }
        static var subsection: Font { .custom("Helvetica Neue", fixedSize: 12 * s) }
        static var status: Font { .custom("Helvetica Neue", fixedSize: 7 * s) }
        static var aboutDescription: Font { .custom("Helvetica Neue", fixedSize: 16 * s) }
        static var aboutMetadata: Font { .custom("Helvetica Neue", fixedSize: 16 * s) }
        static var aboutName: Font { .custom("HelveticaNeue-Bold", fixedSize: 12 * s) }
    }
}

final class InterfaceScaleStore: ObservableObject {
    nonisolated(unsafe) static let shared = InterfaceScaleStore()
    @Published private var value: CGFloat = 1
    static var current: CGFloat {
        get { shared.value }
        set { if shared.value != newValue { shared.value = newValue } }
    }
    nonisolated(unsafe) static var availableWindowSize: NSSize?
}

struct SettingsView: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    @ObservedObject var settings: SettingsService
    @ObservedObject var accessibility: AccessibilityService
    @ObservedObject var menuBarService: MenuBarService

    private var selection: SettingsSection { settings.selectedSection }
    private var language: AppLanguage { settings.preferences.language }
    private func t(_ key: String) -> String { L10n.text(key, language: language) }
    @State private var confirmReset = false
    @State private var confirmAppearanceReset = false
    @State private var openSettingsDropdown: String?
    @State private var activeInfoTooltip: SettingsTooltipPayload?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var disclosureAnimation: Animation? {
        settings.preferences.animations && !reduceMotion
            ? .easeInOut(duration: SettingsDesign.Layout.disclosureDuration) : nil
    }
    private func preference<T>(_ keyPath: WritableKeyPath<SettingsPreferences, T>) -> Binding<T> {
        Binding(get: { settings.preferences[keyPath: keyPath] },
                set: { value in settings.updatePreferences { $0[keyPath: keyPath] = value } })
    }
    @State private var ignoredItemsExpanded = true
    @State private var appearanceLayoutExpanded = false
    @State private var privacyDescriptionExpanded = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            windowShell

            sidebar
                .frame(
                    width: SettingsDesign.Layout.sidebarWidth,
                    height: SettingsDesign.Layout.sidebarHeight
                )
                .padding(.leading, SettingsDesign.Layout.sidebarX)
                .padding(.top, SettingsDesign.Layout.sidebarY)

            VStack(alignment: .leading, spacing: 11) {
                Text(selection.title(language: language))
                    .font(SettingsDesign.Typography.pageTitle)
                    .foregroundStyle(SettingsDesign.Colors.primary)
                    .lineLimit(1)
                    .frame(
                        width: SettingsDesign.Layout.contentWidth,
                        height: SettingsDesign.Layout.titleHeight,
                        alignment: .leading
                    )

                ScrollView(.vertical) {
                    content
                        .frame(
                            minWidth: SettingsDesign.Layout.contentWidth,
                            maxWidth: SettingsDesign.Layout.contentWidth,
                            minHeight: SettingsDesign.Layout.panelHeight,
                            alignment: .topLeading
                        )
                }
                .id(selection)
                .frame(
                    width: SettingsDesign.Layout.contentWidth,
                    height: SettingsDesign.Layout.panelHeight,
                    alignment: .topLeading
                )
                .background {
                    LinearGradient(
                        colors: [
                            SettingsDesign.Colors.panelTop,
                            SettingsDesign.Colors.panelBottom
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipShape(RoundedRectangle(
                    cornerRadius: SettingsDesign.Layout.panelCornerRadius,
                    style: .continuous
                ))
            }
            .padding(.leading, SettingsDesign.Layout.contentX)
            .padding(.top, SettingsDesign.Layout.titleY)

            SettingsWindowDragRegion()
                .frame(
                    width: SettingsDesign.Layout.contentWidth,
                    height: SettingsDesign.Layout.headerDragRegionHeight
                )
                .padding(.leading, SettingsDesign.Layout.contentX)
                .accessibilityHidden(true)
        }
        .frame(
            width: SettingsDesign.Layout.windowWidth,
            height: SettingsDesign.Layout.windowHeight
        )
        .overlayPreferenceValue(SettingsTooltipAnchorKey.self) { anchors in
            GeometryReader { geometry in
                if let tooltip = activeInfoTooltip,
                   let anchor = anchors[tooltip.id] {
                    let iconFrame = geometry[anchor]
                    let width: CGFloat = 155 * InterfaceScaleStore.current
                    let gap: CGFloat = 10 * InterfaceScaleStore.current
                    let fitsRight = iconFrame.maxX + gap + width <= geometry.size.width - 8 * InterfaceScaleStore.current
                    SettingsInfoTooltipBubble(text: tooltip.text)
                        .position(
                            x: fitsRight
                                ? iconFrame.maxX + gap + width / 2
                                : iconFrame.minX - gap - width / 2,
                            y: iconFrame.midY
                        )
                        .transition(.opacity.combined(with: .offset(x: fitsRight ? -3 : 3)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .environment(\.noMenuAnimationsEnabled, settings.preferences.animations && !reduceMotion)
        .transaction { if !settings.preferences.animations || reduceMotion { $0.disablesAnimations = true } }
        .onChange(of: selection) { _, _ in activeInfoTooltip = nil }
        .onChange(of: settings.preferences.interfaceSize) { _, _ in
            activeInfoTooltip = nil
            openSettingsDropdown = nil
        }
        .onChange(of: language) { _, _ in
            activeInfoTooltip = nil
            openSettingsDropdown = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            activeInfoTooltip = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in
            activeInfoTooltip = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            activeInfoTooltip = nil
        }
        .alert("NoMenu", isPresented: Binding(
            get: { settings.actionMessage != nil },
            set: { if !$0 { settings.actionMessage = nil } }
        )) {
            Button(t("OK"), role: .cancel) { settings.actionMessage = nil }
        } message: { Text(settings.actionMessage ?? "") }
        .confirmationDialog(t("Reset NoMenu preferences and cached state?"), isPresented: $confirmReset) {
            Button(t("Reset NoMenu State"), role: .destructive) {
                do {
                    try settings.resetNoMenuState()
                    menuBarService.clearArtworkCache(refreshAfterward: false)
                    menuBarService.restartDiscovery()
                } catch { settings.actionMessage = error.localizedDescription }
            }
            Button(t("Cancel"), role: .cancel) {}
        } message: {
            Text(t("Only NoMenu preferences, ignored items and artwork are reset. macOS permissions are not changed."))
        }
        .confirmationDialog(t("Reset Appearance & Layout?"), isPresented: $confirmAppearanceReset) {
            Button(t("Reset Appearance & Layout"), role: .destructive) {
                settings.resetBarAppearanceAndLayout()
            }
            Button(t("Cancel"), role: .cancel) {}
        } message: {
            Text(t("Only NoMenu bar appearance and layout settings will be reset."))
        }
        .onAppear {
            settings.refreshRuntimeState()
            menuBarService.setIgnoredItemIDs(settings.ignoredItemIDs)
            menuBarService.setHoverHighlightEnabled(settings.hoverHighlightEnabled)
        }
        .task {
            while !Task.isCancelled {
                settings.refreshRuntimeState()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .alert(t("Couldn’t update Login Items"), isPresented: Binding(
            get: { settings.launchAtLoginError != nil },
            set: { if !$0 { settings.clearLaunchAtLoginError() } }
        )) {
            Button(t("OK"), role: .cancel) { settings.clearLaunchAtLoginError() }
        } message: {
            Text(settings.launchAtLoginError ?? t("Unknown error"))
        }
    }

    private var windowShell: some View {
        ZStack(alignment: .topLeading) {
            SettingsDesign.Colors.leftShellTint
                .frame(
                    width: SettingsDesign.Layout.leftRegionWidth,
                    height: SettingsDesign.Layout.windowHeight
                )
                .mask(alignment: .topLeading) {
                    RoundedRectangle(
                        cornerRadius: SettingsDesign.Layout.outerCornerRadius,
                        style: .continuous
                    )
                    .frame(
                        width: SettingsDesign.Layout.windowWidth,
                        height: SettingsDesign.Layout.windowHeight
                    )
                }

            SettingsDesign.Colors.rightShell
                .frame(
                    width: SettingsDesign.Layout.windowWidth
                        - SettingsDesign.Layout.leftRegionWidth,
                    height: SettingsDesign.Layout.windowHeight
                )
                .padding(.leading, SettingsDesign.Layout.leftRegionWidth)
                .mask(alignment: .topLeading) {
                RoundedRectangle(
                    cornerRadius: SettingsDesign.Layout.outerCornerRadius,
                    style: .continuous
                )
                .frame(
                    width: SettingsDesign.Layout.windowWidth,
                    height: SettingsDesign.Layout.windowHeight
                )
            }

            RoundedRectangle(
                cornerRadius: SettingsDesign.Layout.outerCornerRadius,
                style: .continuous
            )
            .strokeBorder(Color.black.opacity(0.30), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    SettingsDesign.Colors.sidebarTop,
                    SettingsDesign.Colors.sidebarBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: SettingsDesign.Layout.navigationRowSpacing) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        settings.selectSection(section)
                    } label: {
                        HStack(spacing: SettingsDesign.Layout.navigationIconToText) {
                            SettingsNavigationIcon(section: section)
                                .fixedSize()
                            Text(section.sidebarTitle(language: language))
                                .font(SettingsDesign.Typography.navigation)
                                .foregroundStyle(SettingsDesign.Colors.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, SettingsDesign.Layout.navigationIconInset)
                        .frame(
                            width: SettingsDesign.Layout.navigationWidth,
                            height: SettingsDesign.Layout.navigationRowHeight
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(NavigationNeutralPressStyle())
                    .frame(
                        width: SettingsDesign.Layout.navigationWidth,
                        height: SettingsDesign.Layout.navigationRowHeight
                    )
                    .contentShape(Capsule())
                    .anchorPreference(key: NavigationRowBounds.self, value: .bounds) {
                        [section: $0]
                    }
                    .accessibilityLabel(section.title(language: language))
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
            .backgroundPreferenceValue(NavigationRowBounds.self) { bounds in
                GeometryReader { geometry in
                    if let anchor = bounds[selection] {
                        let destination = geometry[anchor]
                        Capsule()
                            .fill(SettingsDesign.Colors.selection)
                            .frame(width: destination.width, height: destination.height)
                            .position(x: destination.midX, y: destination.midY)
                            .animation(
                                settings.preferences.animations && !reduceMotion
                                    ? .easeInOut(duration: 0.24) : nil,
                                value: destination
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(
                width: SettingsDesign.Layout.navigationWidth,
                alignment: .topLeading
            )
            .padding(.leading, SettingsDesign.Layout.navigationX)
            .padding(.top, SettingsDesign.Layout.navigationY)
            .frame(
                width: SettingsDesign.Layout.sidebarWidth,
                height: SettingsDesign.Layout.sidebarHeight,
                alignment: .topLeading
            )
        }
        .frame(
            width: SettingsDesign.Layout.sidebarWidth,
            height: SettingsDesign.Layout.sidebarHeight,
            alignment: .topLeading
        )
        .clipShape(RoundedRectangle(
            cornerRadius: SettingsDesign.Layout.sidebarCornerRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: SettingsDesign.Layout.sidebarCornerRadius,
                style: .continuous
            )
            .strokeBorder(
                SettingsDesign.Colors.sidebarBorder,
                lineWidth: SettingsDesign.Layout.sidebarBorderWidth
            )
            .shadow(color: SettingsDesign.Colors.sidebarGlow, radius: 4, x: 0, y: 1)
        }
    }

    private struct NavigationNeutralPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }

    private struct NavigationRowBounds: PreferenceKey {
        static var defaultValue: [SettingsSection: Anchor<CGRect>] { [:] }

        static func reduce(value: inout [SettingsSection: Anchor<CGRect>],
                           nextValue: () -> [SettingsSection: Anchor<CGRect>]) {
            value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
        }
    }

    private struct SettingsNavigationIcon: View {
        @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
        let section: SettingsSection

        var body: some View {
            ZStack {
                if section == .menuBar {
                    Image(nsImage: Self.menuBarArtwork)
                        .resizable()
                        .interpolation(.high)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(iconBackground)
                Image(systemName: section.symbolName)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(iconForeground)
                    .symbolRenderingMode(.monochrome)
                }
            }
            .frame(
                width: SettingsDesign.Layout.navigationIconSize,
                height: SettingsDesign.Layout.navigationIconSize
            )
        }

        // Supplied high-resolution Frame 36 PNG, displayed in the unchanged navigation frame.
        private static let menuBarArtwork = NSImage(data: Data(base64Encoded: "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")!)!

        private var iconBackground: some ShapeStyle {
            switch section {
            case .general:
                return AnyShapeStyle(LinearGradient(
                    colors: [Color(white: 0.46), Color(white: 0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            case .menuBar:
                return AnyShapeStyle(LinearGradient(
                    colors: [Color(white: 0.49), Color(white: 0.20)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            case .interaction:
                return AnyShapeStyle(LinearGradient(
                    colors: [Color(red: 0.25, green: 0.84, blue: 0.97), Color(red: 0.05, green: 0.53, blue: 0.83)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            case .permissions:
                return AnyShapeStyle(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.49, blue: 0.49), Color(red: 0.93, green: 0.25, blue: 0.27)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            case .about:
                return AnyShapeStyle(LinearGradient(
                    colors: [Color(white: 0.42), Color(white: 0.20)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
        }

        private var iconForeground: Color {
            switch section {
            case .interaction, .permissions:
                return .black
            default:
                return .white
            }
        }

        private var symbolSize: CGFloat {
            switch section {
            case .general: return 13 * InterfaceScaleStore.current
            case .menuBar, .about: return 10 * InterfaceScaleStore.current
            case .interaction: return 14 * InterfaceScaleStore.current
            case .permissions: return 13 * InterfaceScaleStore.current
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:
            generalContent
        case .menuBar:
            menuBarContent
        case .interaction:
            interactionContent
        case .permissions:
            permissionsContent
        case .about:
            aboutContent
        }
    }

    private var generalContent: some View {
        VStack(spacing: 0) {
            SettingsRow(t("Launch at Login")) {
                SettingsInfoControl(
                    id: "launchAtLogin",
                    text: t("Automatically starts NoMenu when you log in to your Mac."),
                    activeTooltip: $activeInfoTooltip
                ) {
                    SettingsToggle(
                        isOn: Binding(
                            get: { settings.launchAtLoginEnabled },
                            set: { try? settings.setLaunchAtLogin($0) }
                        ),
                        accessibilityLabel: t("Launch at Login")
                    )
                }
            }
            SettingsRow(t("Check for Updates Automatically")) {
                SettingsInfoControl(
                    id: "automaticUpdates",
                    text: t("Periodically checks for new NoMenu updates in the background."),
                    activeTooltip: $activeInfoTooltip
                ) {
                    SettingsToggle(
                        isOn: Binding(
                            get: { settings.automaticUpdateChecksEnabled },
                            set: { settings.setAutomaticUpdateChecks($0) }
                        ),
                        accessibilityLabel: t("Check for Updates Automatically")
                    )
                }
            }
            SettingsRow(t("Check for Updates Now")) {
                SettingsInfoControl(
                    id: "checkUpdatesNow",
                    text: t("Checks for an available NoMenu update now."),
                    activeTooltip: $activeInfoTooltip
                ) {
                    SettingsActionButton(
                        accessibilityLabel: t("Check for Updates Now"),
                        isEnabled: !settings.updateCheckInProgress
                    ) {
                        settings.checkForUpdatesNow()
                    }
                }
            }
            SettingsRow(t("Open NoMenu on Launch")) {
                SettingsInfoControl(
                    id: "openOnLaunch",
                    text: t("Automatically opens the NoMenu interface when the app launches."),
                    activeTooltip: $activeInfoTooltip
                ) {
                    SettingsToggle(
                        isOn: Binding(
                            get: { settings.openNoMenuOnLaunch },
                            set: { settings.setOpenNoMenuOnLaunch($0) }
                        ),
                        accessibilityLabel: t("Open NoMenu on Launch")
                    )
                }
            }
            SettingsRow(t("Remember Last Settings Page")) {
                SettingsInfoControl(
                    id: "rememberLastPage",
                    text: t("Reopens Settings on the page you viewed most recently."),
                    activeTooltip: $activeInfoTooltip
                ) {
                    SettingsToggle(isOn: preference(\.rememberLastPage), accessibilityLabel: t("Remember Last Settings Page"))
                }
            }
            SettingsRow(t("Animations")) {
                SettingsInfoControl(
                    id: "animations",
                    text: t("Enables interface animations throughout NoMenu."),
                    activeTooltip: $activeInfoTooltip
                ) {
                    SettingsToggle(isOn: preference(\.animations), accessibilityLabel: t("Animations"))
                }
            }
            SettingsPickerRow(
                title: t("Interface Size"), infoID: "interfaceSize",
                infoText: t("Changes the size of NoMenu controls, text, and hit targets."),
                selection: preference(\.interfaceSize), openDropdown: $openSettingsDropdown,
                activeTooltip: $activeInfoTooltip, language: language
            )
            SettingsPickerRow(
                title: t("Language"), infoID: "language",
                infoText: t("Changes the language used by NoMenu."),
                selection: preference(\.language), openDropdown: $openSettingsDropdown,
                activeTooltip: $activeInfoTooltip, language: language
            )
            if reduceMotion {
                settingsNote(t("macOS Reduce Motion is enabled."))
            }
            Spacer()
        }
        .padding(.horizontal, SettingsDesign.Layout.wideHorizontalPadding)
        .padding(.top, SettingsDesign.Layout.panelTopPadding)
        .onDisappear { activeInfoTooltip = nil }
    }

    private var menuBarContent: some View {
        VStack(spacing: 0) {
            SettingsRow(t("Refresh Now")) {
                SettingsActionButton(accessibilityLabel: t("Refresh Now")) {
                    menuBarService.refreshFromSettings()
                }
            }
            .padding(.horizontal, SettingsDesign.Layout.compactRowInset)

            SettingsRow(t("Ignored Items")) {
                SettingsInfoControl(
                    id: "ignoredItems",
                    text: t("Menu bar items excluded from NoMenu until you reset them."),
                    activeTooltip: $activeInfoTooltip
                ) {
                    SettingsDisclosureButton(
                        isExpanded: ignoredItemsExpanded,
                        accessibilityLabel: t("Ignored Items"),
                        usesStandardDirection: true
                    ) {
                        if ignoredItemsExpanded {
                            withAnimation(disclosureAnimation) {
                                ignoredItemsExpanded = false
                            }
                        } else {
                            ignoredItemsExpanded = true
                        }
                    }
                }
            }
            .padding(.horizontal, SettingsDesign.Layout.compactRowInset)

            VStack(spacing: 0) {
                ignoredItemsContainer
                    .frame(height: SettingsDesign.Layout.disclosureContentHeight)
                    .padding(.vertical, SettingsDesign.Layout.disclosureVerticalInset)
            }
                .opacity(ignoredItemsExpanded ? 1 : 0)
                .frame(
                    height: ignoredItemsExpanded
                        ? SettingsDesign.Layout.disclosureExpandedExtent
                        : 0,
                    alignment: .top
                )
                .clipped()
                .allowsHitTesting(ignoredItemsExpanded)
                .accessibilityHidden(!ignoredItemsExpanded)
                .animation(
                    disclosureAnimation,
                    value: ignoredItemsExpanded
                )

            SettingsRow(t("Reset Ignored Items")) {
                SettingsActionButton(accessibilityLabel: t("Reset Ignored Items")) {
                    settings.resetIgnoredItems()
                    menuBarService.setIgnoredItemIDs(settings.ignoredItemIDs)
                    menuBarService.refreshFromSettings()
                }
            }
            .padding(.horizontal, SettingsDesign.Layout.compactRowInset)
            SettingsInfoValueRow(
                title: t("Detected Items"), value: "\(menuBarService.items.count)",
                id: "detectedItems",
                text: t("The total number of menu bar items currently detected by NoMenu."),
                activeTooltip: $activeInfoTooltip
            )
                .padding(.horizontal, SettingsDesign.Layout.compactRowInset)
            SettingsInfoValueRow(
                title: t("Overflowed Items"), value: "\(menuBarService.overflowItems.count)",
                id: "overflowedItems",
                text: t("The number of detected menu bar items currently unavailable in the visible menu bar."),
                activeTooltip: $activeInfoTooltip
            )
                .padding(.horizontal, SettingsDesign.Layout.compactRowInset)

            SettingsRow(t("Appearance & Layout")) {
                SettingsDisclosureButton(
                    isExpanded: appearanceLayoutExpanded,
                    accessibilityLabel: t("Appearance & Layout"),
                    usesStandardDirection: true
                ) {
                    withAnimation(disclosureAnimation) {
                        appearanceLayoutExpanded.toggle()
                        openSettingsDropdown = nil
                        activeInfoTooltip = nil
                    }
                }
            }
            .padding(.horizontal, SettingsDesign.Layout.compactRowInset)

            VStack(spacing: 0) {
                barAppearanceContent
                    .frame(height: 425 * InterfaceScaleStore.current, alignment: .top)
            }
            .opacity(appearanceLayoutExpanded ? 1 : 0)
            .frame(height: appearanceLayoutExpanded ? 435 * InterfaceScaleStore.current : 0,
                   alignment: .top)
            .clipped()
            .allowsHitTesting(appearanceLayoutExpanded)
            .accessibilityHidden(!appearanceLayoutExpanded)
            .animation(disclosureAnimation, value: appearanceLayoutExpanded)

            VStack(spacing: 0) {
                SettingsPickerRow(title: t("Item Order"), infoID: "itemOrder", infoText: t("Controls how items are arranged inside NoMenu."), selection: preference(\.itemOrder), openDropdown: $openSettingsDropdown, activeTooltip: $activeInfoTooltip, language: language)
                SettingsPickerRow(title: t("Icon Spacing"), infoID: "iconSpacing", infoText: t("Controls the spacing between items inside NoMenu."), selection: preference(\.iconSpacing), openDropdown: $openSettingsDropdown, activeTooltip: $activeInfoTooltip, language: language)
                SettingsPickerRow(title: t("Icon Appearance"), infoID: "iconAppearance", infoText: t("Chooses whether NoMenu uses captured artwork or an app icon fallback."), selection: preference(\.iconAppearance), openDropdown: $openSettingsDropdown, activeTooltip: $activeInfoTooltip, language: language, options: IconAppearance.supportedCases)
                SettingsPickerRow(title: t("Live Artwork Frame Rate"), infoID: "liveArtworkFPS", infoText: t("Controls how often live menu bar artwork is refreshed. Higher frame rates may use more system resources."), selection: preference(\.liveArtworkFrameRate), openDropdown: $openSettingsDropdown, activeTooltip: $activeInfoTooltip, language: language)
                settingsNote(t("Higher frame rates may increase energy usage."))
                if settings.preferences.iconAppearance == .captured {
                    settingsNote(t("Uses live artwork when screen pixels are available; otherwise cached artwork or an app icon. Requires Screen Recording permission."))
                }
                SettingsRow(t("Show Item Name on Hover")) {
                    SettingsInfoControl(
                        id: "showItemNameOnHover",
                        text: t("Shows an item's name while the pointer rests over it in NoMenu."),
                        activeTooltip: $activeInfoTooltip
                    ) {
                        SettingsToggle(isOn: preference(\.showItemNames), accessibilityLabel: t("Show Item Name on Hover"), darkOffTrack: true)
                    }
                }
            }
            .padding(.horizontal, SettingsDesign.Layout.compactRowInset)
            Spacer()
        }
        .padding(.horizontal, SettingsDesign.Layout.compactHorizontalPadding)
        .padding(.top, SettingsDesign.Layout.panelTopPadding)
    }

    private var barAppearanceContent: some View {
        VStack(spacing: 0) {
            NoMenuBarPreview(preferences: settings.preferences)
                .frame(height: 70 * InterfaceScaleStore.current)
                .padding(.bottom, 5 * InterfaceScaleStore.current)
            SettingsPickerRow(
                title: t("Background Style"), infoID: "barBackgroundStyle",
                infoText: t("Controls what NoMenu's translucent background visually adapts to."),
                selection: preference(\.barBackgroundStyle), openDropdown: $openSettingsDropdown,
                activeTooltip: $activeInfoTooltip, language: language
            )
            SettingsTransparencyRow(
                title: t("Transparency"), infoText: t("Controls how much of the background is visible through NoMenu."),
                value: preference(\.barTransparency), activeTooltip: $activeInfoTooltip
            )
            SettingsPickerRow(
                title: t("Background Blur"), infoID: "barBackgroundBlur",
                infoText: t("Controls how strongly the background behind NoMenu is blurred. This is independent of transparency."),
                selection: preference(\.barBackgroundBlur), openDropdown: $openSettingsDropdown,
                activeTooltip: $activeInfoTooltip, language: language
            )
            SettingsPickerRow(
                title: t("Bar Position"), infoID: "barPosition",
                infoText: t("Controls where NoMenu appears horizontally on the active display."),
                selection: preference(\.barPosition), openDropdown: $openSettingsDropdown,
                activeTooltip: $activeInfoTooltip, language: language
            )
            SettingsPickerRow(
                title: t("Screen Edge Margin"), infoID: "barEdgeMargin",
                infoText: t("Controls the space between NoMenu and the display edge."),
                selection: preference(\.barEdgeMargin), openDropdown: $openSettingsDropdown,
                activeTooltip: $activeInfoTooltip, language: language
            )
            SettingsPickerRow(
                title: t("Bar Size"), infoID: "barSize",
                infoText: t("Changes NoMenu's visual size without changing the macOS menu bar."),
                selection: preference(\.barSize), openDropdown: $openSettingsDropdown,
                activeTooltip: $activeInfoTooltip, language: language
            )
            SettingsPickerRow(
                title: t("Width"), infoID: "barWidth",
                infoText: t("Controls how much horizontal space the NoMenu bar uses."),
                selection: preference(\.barWidth), openDropdown: $openSettingsDropdown,
                activeTooltip: $activeInfoTooltip, language: language
            )
            SettingsRow(t("Reset Appearance & Layout")) {
                SettingsActionButton(accessibilityLabel: t("Reset Appearance & Layout")) {
                    confirmAppearanceReset = true
                }
            }
        }
        .padding(10 * InterfaceScaleStore.current)
        .background(SettingsDesign.Colors.insetPanel)
        .clipShape(RoundedRectangle(
            cornerRadius: SettingsDesign.Layout.disclosureCornerRadius,
            style: .continuous
        ))
    }

    private var ignoredItemsContainer: some View {
        Group {
            if menuBarService.ignoredItems.isEmpty {
                Color.clear
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 5 * InterfaceScaleStore.current) {
                        ForEach(menuBarService.ignoredItems) { item in
                            HStack(spacing: 9 * InterfaceScaleStore.current) {
                                Group {
                                    if let icon = menuBarService.icon(for: item) {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .interpolation(.high)
                                    } else {
                                        Image(systemName: item.symbolName)
                                            .resizable()
                                            .scaledToFit()
                                    }
                                }
                                .frame(width: 18 * InterfaceScaleStore.current, height: 18 * InterfaceScaleStore.current)
                                Text(item.name)
                                    .font(.system(size: 11 * InterfaceScaleStore.current, weight: .medium))
                                    .foregroundStyle(SettingsDesign.Colors.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 25 * InterfaceScaleStore.current)
                        }
                    }
                    .padding(14 * InterfaceScaleStore.current)
                }
            }
        }
        .background(SettingsDesign.Colors.insetPanel)
        .clipShape(RoundedRectangle(
            cornerRadius: SettingsDesign.Layout.disclosureCornerRadius,
            style: .continuous
        ))
    }

    private var interactionContent: some View {
        VStack(spacing: 0) {
            SettingsRow(t("Hover Highlight")) {
                SettingsInfoControl(
                    id: "hoverHighlight",
                    text: t("Highlights a NoMenu item while the pointer is over it."),
                    activeTooltip: $activeInfoTooltip
                ) {
                    SettingsToggle(
                        isOn: Binding(
                            get: { settings.hoverHighlightEnabled },
                            set: { enabled in
                                settings.setHoverHighlight(enabled)
                                menuBarService.setHoverHighlightEnabled(enabled)
                            }
                        ),
                        accessibilityLabel: t("Hover Highlight")
                    )
                }
            }

            SettingsRow(t("Keyboard Shortcut")) {
                SettingsInfoControl(
                    id: "keyboardShortcut",
                    text: t("Sets a keyboard shortcut for opening and closing NoMenu."),
                    activeTooltip: $activeInfoTooltip
                ) {
                    SettingsShortcutRecorder(settings: settings)
                        .frame(width: 125 * InterfaceScaleStore.current, height: 24 * InterfaceScaleStore.current)
                }
            }
            settingsNote(t("Click to record. Use Command or Control; Delete clears."))
            if let error = settings.shortcutError { settingsNote(error) }
            SettingsRow(t("Close with Escape")) {
                SettingsInfoControl(
                    id: "closeWithEscape",
                    text: t("Closes NoMenu when you press the Escape key."),
                    activeTooltip: $activeInfoTooltip
                ) {
                    SettingsToggle(isOn: preference(\.closeWithEscape), accessibilityLabel: t("Close with Escape"))
                }
            }
            SettingsRow(t("Keep NoMenu Open After Activation")) {
                SettingsInfoControl(
                    id: "keepOpenAfterActivation",
                    text: t("Keeps NoMenu visible after you activate one of its items."),
                    activeTooltip: $activeInfoTooltip
                ) {
                    SettingsToggle(isOn: preference(\.keepOpenAfterActivation), accessibilityLabel: t("Keep NoMenu Open After Activation"))
                }
            }
            HStack(spacing: 17 * InterfaceScaleStore.current) {
                Text(t("Behavior"))
                    .font(SettingsDesign.Typography.subsection)
                    .foregroundStyle(SettingsDesign.Colors.secondary)
                Rectangle()
                    .fill(SettingsDesign.Colors.divider)
                    .frame(height: 1)
            }
            .frame(height: SettingsDesign.Layout.behaviorHeaderHeight)
            .padding(.leading, -10 * InterfaceScaleStore.current)
            .padding(.trailing, -4 * InterfaceScaleStore.current)

            SettingsInfoValueRow(
                title: t("Click Outside to Dismiss"), value: t("active"),
                id: "outsideDismiss",
                text: t("This active behavior closes NoMenu when you click outside it."),
                activeTooltip: $activeInfoTooltip, muted: true
            )
            SettingsInfoValueRow(
                title: t("Direct Item Switching"), value: t("active"),
                id: "directItemSwitching",
                text: t("This active behavior lets you switch directly between NoMenu items."),
                activeTooltip: $activeInfoTooltip, muted: true
            )
            Spacer()
        }
        .padding(.horizontal, SettingsDesign.Layout.wideHorizontalPadding)
        .padding(.top, SettingsDesign.Layout.panelTopPadding)
    }

    private var permissionsContent: some View {
        VStack(spacing: 0) {
            PermissionRow(
                title: t("Accessibility"),
                isActive: accessibility.isTrusted,
                accessibilityLabel: t("Accessibility Settings"),
                infoID: "accessibilityPermission",
                infoText: t("Allows NoMenu to detect and interact with menu bar items."),
                activeTooltip: $activeInfoTooltip,
                language: language
            ) {
                if !accessibility.isTrusted {
                    accessibility.requestPermission()
                }
                settings.openAccessibilitySettings()
            }
            .padding(.horizontal, SettingsDesign.Layout.compactRowInset)

            PermissionRow(
                title: t("Screen Recording"),
                isActive: settings.screenRecordingAuthorized,
                accessibilityLabel: t("Screen Recording Settings"),
                infoID: "screenRecordingPermission",
                infoText: t("Allows NoMenu to capture menu bar item artwork for Live Artwork when available."),
                activeTooltip: $activeInfoTooltip,
                language: language
            ) {
                settings.requestOrOpenScreenRecordingSettings()
            }
            .padding(.horizontal, SettingsDesign.Layout.compactRowInset)

            SettingsRow(t("Re-check Permissions")) {
                SettingsActionButton(accessibilityLabel: t("Re-check Permissions")) {
                    _ = accessibility.refreshAccessibilityState(reason: "Re-check Permissions")
                    settings.refreshScreenRecordingStatus()
                }
            }
            .padding(.horizontal, SettingsDesign.Layout.compactRowInset)
            SettingsRow(t("Open Privacy Settings")) {
                SettingsActionButton(accessibilityLabel: t("Open Privacy Settings")) {
                    settings.openAccessibilitySettings()
                }
            }
            .padding(.horizontal, SettingsDesign.Layout.compactRowInset)
            SettingsRow(t("Privacy Description")) {
                SettingsDisclosureButton(
                    isExpanded: privacyDescriptionExpanded,
                    accessibilityLabel: t("Privacy Description")
                ) {
                    if privacyDescriptionExpanded {
                        withAnimation(disclosureAnimation) {
                            privacyDescriptionExpanded = false
                        }
                    } else {
                        privacyDescriptionExpanded = true
                    }
                }
            }
            .padding(.horizontal, SettingsDesign.Layout.compactRowInset)

            VStack(spacing: 0) {
                Text(t("NoMenu uses Accessibility to detect menu bar items. All information is processed locally on your Mac.\n\nScreen Recording is used only to capture menu-bar-item artwork when permission is available."))
                    .font(SettingsDesign.Typography.row)
                    .foregroundStyle(SettingsDesign.Colors.secondary)
                    .padding(18 * InterfaceScaleStore.current)
                    .frame(maxWidth: .infinity)
                    .frame(height: SettingsDesign.Layout.disclosureContentHeight)
                    .background(SettingsDesign.Colors.insetPanel)
                    .clipShape(RoundedRectangle(
                        cornerRadius: SettingsDesign.Layout.disclosureCornerRadius,
                        style: .continuous
                    ))
                    .padding(.vertical, SettingsDesign.Layout.disclosureVerticalInset)
            }
                .opacity(privacyDescriptionExpanded ? 1 : 0)
                .frame(
                    height: privacyDescriptionExpanded
                        ? SettingsDesign.Layout.disclosureExpandedExtent
                        : 0,
                    alignment: .top
                )
                .clipped()
                .allowsHitTesting(privacyDescriptionExpanded)
                .accessibilityHidden(!privacyDescriptionExpanded)
                .animation(
                    disclosureAnimation,
                    value: privacyDescriptionExpanded
                )
            VStack(spacing: 0) {
                SettingsRow(t("Diagnostic Logging")) {
                    SettingsInfoControl(
                        id: "diagnosticLogging",
                        text: t("Records additional local diagnostic events to help troubleshoot NoMenu."),
                        activeTooltip: $activeInfoTooltip
                    ) {
                        SettingsToggle(isOn: preference(\.diagnosticLogging), accessibilityLabel: t("Diagnostic Logging"))
                    }
                }
                SettingsRow(t("Copy Diagnostic Report")) {
                    SettingsActionButton(accessibilityLabel: t("Copy Diagnostic Report")) {
                        if let report = settings.diagnosticReportProvider?() { settings.copyText(report) }
                        else { settings.actionMessage = t("Diagnostic report is not available.") }
                    }
                }
                SettingsRow(t("Restart Menu Bar Discovery")) {
                    SettingsActionButton(accessibilityLabel: t("Restart Menu Bar Discovery")) {
                        menuBarService.restartDiscovery()
                    }
                }
                SettingsRow(t("Clear Artwork Cache")) {
                    SettingsActionButton(accessibilityLabel: t("Clear Artwork Cache")) {
                        menuBarService.clearArtworkCache()
                    }
                }
                SettingsRow(t("Reset NoMenu State")) {
                    SettingsActionButton(accessibilityLabel: t("Reset NoMenu State")) { confirmReset = true }
                }
            }
            .padding(.horizontal, SettingsDesign.Layout.compactRowInset)
            Spacer()
        }
        .padding(.horizontal, SettingsDesign.Layout.compactHorizontalPadding)
        .padding(.top, SettingsDesign.Layout.panelTopPadding)
    }

    private var aboutContent: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 7 * InterfaceScaleStore.current) {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: SettingsDesign.Layout.aboutIconSize,
                        height: SettingsDesign.Layout.aboutIconSize
                    )
                Text("NoMenu")
                    .font(SettingsDesign.Typography.aboutName)
                    .foregroundStyle(SettingsDesign.Colors.primary)
            }
            .frame(
                width: SettingsDesign.Layout.aboutHeaderWidth,
                height: SettingsDesign.Layout.aboutHeaderHeight
            )
            .background(Color.black.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .offset(
                x: SettingsDesign.Layout.aboutHeaderX,
                y: SettingsDesign.Layout.aboutHeaderY
            )

            VStack(spacing: 18 * InterfaceScaleStore.current) {
                Text(t("A lightweight menu bar utility\nfor accessing hidden menu bar items."))
                Text(t("Designed to keep your menu bar\nclean while keeping important tools within\neasy reach."))
            }
            .font(SettingsDesign.Typography.aboutDescription)
            .foregroundStyle(Color.white.opacity(0.88))
            .multilineTextAlignment(.center)
            .lineSpacing(2 * InterfaceScaleStore.current)
            .frame(width: SettingsDesign.Layout.contentWidth)
            .offset(y: 180 * InterfaceScaleStore.current)

            VStack(spacing: 3 * InterfaceScaleStore.current) {
                Text("\(t("Build")) \(bundleBuild)")
                Text("\(t("Version")) \(bundleVersion)")
                Group {
                    Text("macOS \(currentMacOSVersion)")
                    Text(minimumMacOSDescription)
                }
                .font(.system(size: 10 * InterfaceScaleStore.current))
                .foregroundStyle(Color.white.opacity(0.60))
                Button(t("Copy Version Info")) { settings.copyText(aboutVersionInfo) }
                    .buttonStyle(.plain)
                    .font(SettingsDesign.Typography.row)
                    .padding(.horizontal, 12 * InterfaceScaleStore.current)
                    .padding(.vertical, 4 * InterfaceScaleStore.current)
                    .background(SettingsDesign.Colors.control, in: Capsule())
                Text("© 2026 NoMenu")
                    .font(.system(size: 10 * InterfaceScaleStore.current))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.top, 4 * InterfaceScaleStore.current)
            }
            .font(SettingsDesign.Typography.aboutMetadata)
            .foregroundStyle(Color.white.opacity(0.82))
            .frame(
                width: SettingsDesign.Layout.contentWidth,
                height: SettingsDesign.Layout.panelHeight - 14 * InterfaceScaleStore.current,
                alignment: .bottom
            )
        }
        .frame(
            width: SettingsDesign.Layout.contentWidth,
            height: SettingsDesign.Layout.panelHeight,
            alignment: .topLeading
        )
    }

    private func settingsNote(_ text: String) -> some View {
        Text(text)
            .font(SettingsDesign.Typography.row)
            .foregroundStyle(SettingsDesign.Colors.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5 * InterfaceScaleStore.current)
    }

    private var applicationIcon: NSImage {
        if let url = Bundle.main.url(forResource: "NoMenu", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }

    private var bundleBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var currentMacOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var minimumMacOSDescription: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String else {
            return "Minimum macOS requirement unavailable"
        }
        return language == .korean ? "macOS \(version) 이상 필요" : "Requires macOS \(version) or later"
    }

    private var aboutVersionInfo: String {
        "NoMenu\n\(t("Version")) \(bundleVersion)\n\(t("Build")) \(bundleBuild)\nmacOS \(currentMacOSVersion)\n\(minimumMacOSDescription)"
    }
}

private struct NoMenuAnimationsKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    var noMenuAnimationsEnabled: Bool {
        get { self[NoMenuAnimationsKey.self] }
        set { self[NoMenuAnimationsKey.self] = newValue }
    }
}

private struct SettingsPickerRow<Option: SettingsPickerOption>: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let title: String
    let infoID: String
    let infoText: String
    @Binding var selection: Option
    @Binding var openDropdown: String?
    @Binding var activeTooltip: SettingsTooltipPayload?
    let language: AppLanguage
    var options: [Option] = Array(Option.allCases)
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(SettingsDesign.Typography.row)
                .foregroundStyle(SettingsDesign.Colors.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: SettingsDesign.Layout.rowHeight, alignment: .leading)
            SettingsInfoControl(id: infoID, text: infoText, activeTooltip: $activeTooltip) {
                SettingsNativePicker(title: title, selection: $selection,
                                     openDropdown: $openDropdown, language: language, options: options)
                    .padding(.vertical, (SettingsDesign.Layout.rowHeight - SettingsDesign.Layout.actionHeight) / 2)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .onDisappear { if openDropdown == title { openDropdown = nil } }
    }
}

private struct SettingsTransparencyRow: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let title: String
    let infoText: String
    @Binding var value: Double
    @Binding var activeTooltip: SettingsTooltipPayload?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(SettingsDesign.Typography.row)
                .foregroundStyle(SettingsDesign.Colors.primary)
            Spacer(minLength: 8)
            SettingsInfoControl(
                id: "barTransparency", text: infoText,
                activeTooltip: $activeTooltip
            ) {
                HStack(spacing: 6 * InterfaceScaleStore.current) {
                    Slider(value: $value, in: 0.20...0.90, step: 0.05)
                        .frame(
                            width: 86 * InterfaceScaleStore.current,
                            height: SettingsDesign.Layout.actionHeight,
                            alignment: .center
                        )
                        .tint(SettingsDesign.Colors.toggleBlue)
                    Text("\(Int((value * 100).rounded()))%")
                        .font(SettingsDesign.Typography.status)
                        .foregroundStyle(SettingsDesign.Colors.secondary)
                        .frame(width: 28 * InterfaceScaleStore.current, alignment: .trailing)
                }
                .frame(
                    width: 120 * InterfaceScaleStore.current,
                    height: SettingsDesign.Layout.rowHeight,
                    alignment: .center
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: SettingsDesign.Layout.rowHeight,
            maxHeight: SettingsDesign.Layout.rowHeight,
            alignment: .center
        )
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private struct NoMenuBarPreview: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let preferences: SettingsPreferences

    var body: some View {
        GeometryReader { geometry in
            let previewHeight = previewBarHeight
            let previewWidth = min(geometry.size.width - 16, preferredPreviewWidth(in: geometry.size.width))
            HStack {
                if preferences.barPosition != .left { Spacer(minLength: 0) }
                HStack(spacing: previewItemSpacing) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(Color.white.opacity(index == 0 ? 0.96 : 0.74))
                            .frame(width: previewIconSize, height: previewIconSize)
                    }
                }
                .frame(width: previewWidth, height: previewHeight)
                .background {
                    Capsule().fill(previewBackground)
                }
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5) }
                if preferences.barPosition != .right { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private var previewBarHeight: CGFloat {
        switch preferences.barSize { case .compact: 18; case .standard: 22; case .large: 27 }
    }
    private var previewIconSize: CGFloat {
        switch preferences.barSize { case .compact: 7; case .standard: 9; case .large: 11 }
    }
    private var previewItemSpacing: CGFloat {
        switch preferences.iconSpacing { case .compact: 6; case .standard: 10; case .comfortable: 14 }
    }
    private func preferredPreviewWidth(in available: CGFloat) -> CGFloat {
        switch preferences.barWidth {
        case .fitContent: 88
        case .compact: min(150, available * 0.50)
        case .wide: min(250, available * 0.82)
        }
    }
    private var previewBackground: Color {
        let alpha = 1 - preferences.barTransparency * 0.65
        switch preferences.barBackgroundStyle {
        case .current: return Color(white: 0.42).opacity(alpha)
        case .wallpaper: return Color(red: 0.28, green: 0.39, blue: 0.52).opacity(alpha)
        case .noMenu: return Color(red: 0.08, green: 0.09, blue: 0.11).opacity(alpha)
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: SettingsDesign.Layout.rowSpacing) {
            Text(title)
                .font(SettingsDesign.Typography.row)
                .foregroundStyle(SettingsDesign.Colors.primary)
            Spacer(minLength: 8)
            trailing
        }
        .frame(
            maxWidth: .infinity,
            minHeight: SettingsDesign.Layout.rowHeight,
            maxHeight: SettingsDesign.Layout.rowHeight
        )
    }
}

private struct SettingsValueRow: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let title: String
    let value: String
    var muted = false

    var body: some View {
        HStack(spacing: SettingsDesign.Layout.rowSpacing) {
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .frame(width: SettingsDesign.Layout.actionWidth, alignment: .center)
        }
        .font(SettingsDesign.Typography.row)
        .foregroundStyle(
            muted ? SettingsDesign.Colors.secondary : SettingsDesign.Colors.primary
        )
        .frame(
            maxWidth: .infinity,
            minHeight: SettingsDesign.Layout.rowHeight,
            maxHeight: SettingsDesign.Layout.rowHeight
        )
    }
}

private struct SettingsInfoValueRow: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let title: String
    let value: String
    let id: String
    let text: String
    @Binding var activeTooltip: SettingsTooltipPayload?
    var muted = false

    var body: some View {
        HStack(spacing: SettingsDesign.Layout.rowSpacing) {
            Text(title)
            Spacer(minLength: 8)
            SettingsInfoControl(id: id, text: text, activeTooltip: $activeTooltip) {
                Text(value)
                    .frame(width: SettingsDesign.Layout.actionWidth, alignment: .center)
            }
        }
        .font(SettingsDesign.Typography.row)
        .foregroundStyle(muted ? SettingsDesign.Colors.secondary : SettingsDesign.Colors.primary)
        .frame(maxWidth: .infinity,
               minHeight: SettingsDesign.Layout.rowHeight,
               maxHeight: SettingsDesign.Layout.rowHeight)
    }
}

private struct PermissionRow: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let title: String
    let isActive: Bool
    let accessibilityLabel: String
    let infoID: String
    let infoText: String
    @Binding var activeTooltip: SettingsTooltipPayload?
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        HStack(spacing: SettingsDesign.Layout.rowSpacing) {
            Text(title)
                .font(SettingsDesign.Typography.row)
                .foregroundStyle(SettingsDesign.Colors.primary)
            Spacer(minLength: 8)
            SettingsInfoControl(id: infoID, text: infoText, activeTooltip: $activeTooltip) {
                HStack(spacing: SettingsDesign.Layout.rowSpacing) {
                    Text(L10n.text(isActive ? "Granted" : "Not Granted", language: language))
                        .font(SettingsDesign.Typography.status)
                        .foregroundStyle(SettingsDesign.Colors.secondary)
                    SettingsActionButton(
                        accessibilityLabel: accessibilityLabel,
                        action: action
                    )
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: SettingsDesign.Layout.rowHeight,
            maxHeight: SettingsDesign.Layout.rowHeight
        )
    }
}

private struct SettingsTooltipPayload: Equatable {
    let id: String
    let text: String
}

private struct SettingsTooltipAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

private struct SettingsInfoControl<Control: View>: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let id: String
    let text: String
    @Binding var activeTooltip: SettingsTooltipPayload?
    @ViewBuilder let control: () -> Control
    @Environment(\.noMenuAnimationsEnabled) private var animationsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingPresentation: Task<Void, Never>?

    private var appearanceAnimation: Animation? {
        animationsEnabled && !reduceMotion ? .easeOut(duration: 0.15) : nil
    }

    var body: some View {
        HStack(spacing: 8) {
            infoIcon
            control()
        }
        .onDisappear { cancelAndDismiss(animated: false) }
        .onChange(of: text) { _, _ in cancelAndDismiss(animated: false) }
        .onChange(of: InterfaceScaleStore.current) { _, _ in cancelAndDismiss(animated: false) }
    }

    private var infoIcon: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11 * InterfaceScaleStore.current, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.92))
            .frame(width: 24 * InterfaceScaleStore.current, height: 24 * InterfaceScaleStore.current)
            .contentShape(Circle())
            .onHover { hovering in
                if hovering { beginDelayedPresentation() }
                else { cancelAndDismiss(animated: true) }
            }
            .anchorPreference(key: SettingsTooltipAnchorKey.self, value: .bounds) {
                [id: $0]
            }
            .accessibilityLabel(L10n.text("Information"))
            .accessibilityHint(text)
    }

    private func beginDelayedPresentation() {
        pendingPresentation?.cancel()
        if activeTooltip?.id != id {
            withAnimation(appearanceAnimation) { activeTooltip = nil }
        }
        pendingPresentation = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(0.5)) }
            catch { return }
            guard !Task.isCancelled, NSApp.keyWindow?.isVisible == true else { return }
            withAnimation(appearanceAnimation) {
                activeTooltip = SettingsTooltipPayload(id: id, text: text)
            }
        }
    }

    private func cancelAndDismiss(animated: Bool) {
        pendingPresentation?.cancel()
        pendingPresentation = nil
        guard activeTooltip?.id == id else { return }
        withAnimation(animated ? appearanceAnimation : nil) { activeTooltip = nil }
    }
}

private struct SettingsInfoTooltipBubble: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9 * InterfaceScaleStore.current, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.94))
            .multilineTextAlignment(.leading)
            .lineSpacing(1 * InterfaceScaleStore.current)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 139 * InterfaceScaleStore.current, alignment: .leading)
            .padding(.horizontal, 8 * InterfaceScaleStore.current)
            .padding(.vertical, 8 * InterfaceScaleStore.current)
            .background {
                RoundedRectangle(cornerRadius: 6 * InterfaceScaleStore.current, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6 * InterfaceScaleStore.current, style: .continuous)
                            .fill(Color(red: 18 / 255, green: 18 / 255, blue: 19 / 255).opacity(0.88))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6 * InterfaceScaleStore.current, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.34), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(0.24), radius: 5, x: 0, y: 2)
    }
}

private struct SettingsToggle: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    @Environment(\.noMenuAnimationsEnabled) private var animationsEnabled
    @Binding var isOn: Bool
    let accessibilityLabel: String
    var darkOffTrack = false

    var body: some View {
        Button {
            withAnimation(animationsEnabled ? .easeInOut(duration: SettingsDesign.Layout.toggleAnimationDuration) : nil) {
                isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(isOn ? SettingsDesign.Colors.toggleBlue : (darkOffTrack ? SettingsDesign.Colors.control : Color.white.opacity(0.96)))
                Capsule()
                    .strokeBorder(
                        isOn ? Color.white.opacity(0.16) : Color.white.opacity(0.78),
                        lineWidth: 1
                    )
                Circle()
                    .fill(isOn || darkOffTrack ? Color.white : Color.black.opacity(0.48))
                    .frame(
                        width: SettingsDesign.Layout.toggleKnobSize,
                        height: SettingsDesign.Layout.toggleKnobSize
                    )
                    .offset(x: isOn ? toggleKnobOffset : -toggleKnobOffset)
            }
            .frame(
                width: SettingsDesign.Layout.toggleWidth,
                height: SettingsDesign.Layout.toggleHeight
            )
        }
        .buttonStyle(.plain)
        .frame(
            width: SettingsDesign.Layout.toggleWidth,
            height: SettingsDesign.Layout.toggleHeight
        )
        .contentShape(Capsule())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(L10n.text(isOn ? "On" : "Off"))
    }

    private var toggleKnobOffset: CGFloat {
        (SettingsDesign.Layout.toggleWidth - SettingsDesign.Layout.toggleKnobSize) / 2
            - SettingsDesign.Layout.toggleKnobInset
    }
}

private struct SettingsActionButton: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let accessibilityLabel: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(
                    size: SettingsDesign.Layout.actionIconSize,
                    weight: .semibold
                ))
                .foregroundStyle(Color.white.opacity(isEnabled ? 0.94 : 0.42))
                .frame(
                    width: SettingsDesign.Layout.actionWidth,
                    height: SettingsDesign.Layout.actionHeight
                )
                .background(SettingsDesign.Colors.control)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(
            width: SettingsDesign.Layout.actionWidth,
            height: SettingsDesign.Layout.actionHeight
        )
        .contentShape(Capsule())
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SettingsDisclosureButton: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let isExpanded: Bool
    let accessibilityLabel: String
    var usesStandardDirection = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded == usesStandardDirection ? "chevron.up" : "chevron.down")
                .font(.system(
                    size: SettingsDesign.Layout.disclosureIconSize,
                    weight: .bold
                ))
                .foregroundStyle(Color.white.opacity(0.94))
                .frame(
                    width: SettingsDesign.Layout.actionWidth,
                    height: SettingsDesign.Layout.actionHeight
                )
                .background(SettingsDesign.Colors.control)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(
            width: SettingsDesign.Layout.actionWidth,
            height: SettingsDesign.Layout.actionHeight
        )
        .contentShape(Capsule())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(L10n.text(isExpanded ? "Expanded" : "Collapsed"))
    }
}

private struct SettingsWindowDragRegion: NSViewRepresentable {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    func makeNSView(context: Context) -> SettingsWindowDragView {
        let view = SettingsWindowDragView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: SettingsWindowDragView, context: Context) {}
}

private final class SettingsWindowDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        guard let window else {
            super.mouseDown(with: event)
            return
        }
        window.performDrag(with: event)
    }
}
