import Foundation

enum SettingsSection: String, CaseIterable, Identifiable, Codable {
    case general = "General"
    case menuBar = "Menu Bar"
    case interaction = "Interaction"
    case permissions = "Permissions & Privacy"
    case about = "About"
    var id: Self { self }
    func title(language: AppLanguage) -> String { L10n.text(rawValue, language: language) }
    func sidebarTitle(language: AppLanguage) -> String {
        self == .permissions ? L10n.text("Permissions & Pr..", language: language) : title(language: language)
    }
    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .menuBar, .about: "ellipsis"
        case .interaction: "touchid"
        case .permissions: "hand.raised.fill"
        }
    }
}

enum ItemOrder: String, Codable, CaseIterable {
    case menuBar = "Menu Bar Order", recent = "Recently Used", alphabetical = "Alphabetical"
}

enum InterfaceSize: String, Codable, CaseIterable {
    case defaultSize = "Default — 100%"
    case large = "Large — 115%"
    case extraLarge = "Extra Large — 130%"

    var scale: CGFloat {
        switch self { case .defaultSize: 1; case .large: 1.15; case .extraLarge: 1.30 }
    }
}

enum AppLanguage: String, Codable, CaseIterable {
    case english = "English"
    case korean = "한국어"

    var localeIdentifier: String { self == .korean ? "ko" : "en" }
    static var systemDefault: Self {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("ko") == true ? .korean : .english
    }
}

protocol SettingsPickerOption: RawRepresentable, CaseIterable, Hashable where RawValue == String {
    func displayName(language: AppLanguage) -> String
}

extension SettingsPickerOption {
    func displayName(language: AppLanguage) -> String { L10n.text(rawValue, language: language) }
}

extension ItemOrder: SettingsPickerOption {}
extension IconSpacing: SettingsPickerOption {}
extension IconAppearance: SettingsPickerOption {}
extension LiveArtworkFrameRate: SettingsPickerOption {}
extension InterfaceSize: SettingsPickerOption {}
extension AppLanguage: SettingsPickerOption {
    func displayName(language: AppLanguage) -> String { rawValue }
}

enum IconSpacing: String, Codable, CaseIterable {
    case compact = "Compact", standard = "Default", comfortable = "Comfortable"
    var itemWidth: CGFloat {
        switch self { case .compact: 32; case .standard: 38; case .comfortable: 46 }
    }
}

enum IconAppearance: String, Codable, CaseIterable {
    case automatic = "Automatic", captured = "Captured Artwork", appIcon = "App Icon Fallback"
    static var supportedCases: [Self] {
        allCases
    }
}

enum LiveArtworkFrameRate: String, CaseIterable, Codable {
    case five = "5 FPS", ten = "10 FPS", fifteen = "15 FPS", thirty = "30 FPS"
    var framesPerSecond: Int {
        switch self { case .five: 5; case .ten: 10; case .fifteen: 15; case .thirty: 30 }
    }
}

enum NoMenuBackgroundStyle: String, Codable, CaseIterable, SettingsPickerOption {
    case current = "Current Background"
    case wallpaper = "Desktop Wallpaper"
    case noMenu = "NoMenu Background"
}

enum NoMenuBackgroundBlur: String, Codable, CaseIterable, SettingsPickerOption {
    case off = "Off"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

enum NoMenuBarPosition: String, Codable, CaseIterable, SettingsPickerOption {
    case left = "Left"
    case center = "Center"
    case right = "Right"
}

enum NoMenuScreenEdgeMargin: String, Codable, CaseIterable, SettingsPickerOption {
    case compact = "Compact"
    case standard = "Default"
    case spacious = "Spacious"

    var points: CGFloat {
        switch self { case .compact: 12; case .standard: 24; case .spacious: 48 }
    }
}

enum NoMenuBarSize: String, Codable, CaseIterable, SettingsPickerOption {
    case compact = "Compact"
    case standard = "Default"
    case large = "Large"

    var height: CGFloat { switch self { case .compact: 30; case .standard: 36; case .large: 44 } }
    var iconSize: CGFloat { switch self { case .compact: 16; case .standard: 18; case .large: 22 } }
    var itemHeight: CGFloat { switch self { case .compact: 24; case .standard: 28; case .large: 34 } }
    var horizontalPadding: CGFloat { switch self { case .compact: 10; case .standard: 12; case .large: 15 } }
    var itemWidthAdjustment: CGFloat { switch self { case .compact: -4; case .standard: 0; case .large: 6 } }
}

enum NoMenuBarWidth: String, Codable, CaseIterable, SettingsPickerOption {
    case fitContent = "Fit Content"
    case compact = "Compact Width"
    case wide = "Wide"
}

struct NoMenuShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String
}

/// Additional preferences share one versioned record; existing preference keys
/// remain owned by SettingsService. No TCC state is persisted here.
struct SettingsPreferences: Codable, Equatable {
    // Optional storage preserves decoding of the existing versioned record.
    private var storedLiveArtworkFrameRate: LiveArtworkFrameRate?
    var liveArtworkFrameRate: LiveArtworkFrameRate {
        get { storedLiveArtworkFrameRate ?? .ten }
        set { storedLiveArtworkFrameRate = newValue }
    }
    var rememberLastPage = false
    var lastPage: SettingsSection = .general
    var animations = true
    var itemOrder: ItemOrder = .menuBar
    var iconSpacing: IconSpacing = .standard
    var iconAppearance: IconAppearance = .automatic
    var showItemNames = false
    var shortcut: NoMenuShortcut?
    var closeWithEscape = true
    var keepOpenAfterActivation = false
    var diagnosticLogging = false
    var recentlyUsed: [String] = []
    private var storedInterfaceSize: InterfaceSize?
    var interfaceSize: InterfaceSize {
        get { storedInterfaceSize ?? .defaultSize }
        set { storedInterfaceSize = newValue }
    }
    private var storedLanguage: AppLanguage?
    var language: AppLanguage {
        get { storedLanguage ?? .systemDefault }
        set { storedLanguage = newValue }
    }
    private var storedBarBackgroundStyle: NoMenuBackgroundStyle?
    var barBackgroundStyle: NoMenuBackgroundStyle {
        get { storedBarBackgroundStyle ?? .current }
        set { storedBarBackgroundStyle = newValue }
    }
    private var storedBarTransparency: Double?
    var barTransparency: Double {
        get { min(0.90, max(0.20, storedBarTransparency ?? 0.50)) }
        set { storedBarTransparency = min(0.90, max(0.20, newValue)) }
    }
    private var storedBarBackgroundBlur: NoMenuBackgroundBlur?
    var barBackgroundBlur: NoMenuBackgroundBlur {
        get { storedBarBackgroundBlur ?? .medium }
        set { storedBarBackgroundBlur = newValue }
    }
    private var storedBarPosition: NoMenuBarPosition?
    var barPosition: NoMenuBarPosition {
        get { storedBarPosition ?? .right }
        set { storedBarPosition = newValue }
    }
    private var storedBarEdgeMargin: NoMenuScreenEdgeMargin?
    var barEdgeMargin: NoMenuScreenEdgeMargin {
        get { storedBarEdgeMargin ?? .standard }
        set { storedBarEdgeMargin = newValue }
    }
    private var storedBarSize: NoMenuBarSize?
    var barSize: NoMenuBarSize {
        get { storedBarSize ?? .standard }
        set { storedBarSize = newValue }
    }
    private var storedBarWidth: NoMenuBarWidth?
    var barWidth: NoMenuBarWidth {
        get { storedBarWidth ?? .fitContent }
        set { storedBarWidth = newValue }
    }

    mutating func resetBarAppearanceAndLayout() {
        storedBarBackgroundStyle = nil
        storedBarTransparency = nil
        storedBarBackgroundBlur = nil
        storedBarPosition = nil
        storedBarEdgeMargin = nil
        storedBarSize = nil
        storedBarWidth = nil
    }
}
