import CoreGraphics
import Foundation

enum MenuBarItemType: String, Codable, CaseIterable, Sendable {
    case system
    case application
    case controlCenter
    case unknown
}

enum MenuBarVisibilityState: String, Sendable {
    case visible
    case overflowed
    case unknown
}

enum InteractionKind: String, Sendable {
    case menuTree
    case customPopover
    case directPress
    case launchOnly
    case unsupported
}

struct ExternalWindowEvidence: Equatable, Sendable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bounds: CGRect
    let appKitBounds: CGRect
    let layer: Int
    let title: String
}

struct MenuBarItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let stableIdentity: String
    let name: String
    let bundleIdentifier: String?
    let applicationName: String
    let type: MenuBarItemType
    let symbolName: String
    let processIdentifier: pid_t
    let isActionable: Bool
    let isAppleProvided: Bool
    let accessibilityFrame: CGRect?
    let visibilityState: MenuBarVisibilityState
    let visibilityReason: String
    let interactionKind: InteractionKind
    let discoveryOrder: Int

    init(
        id: UUID = UUID(),
        stableIdentity: String? = nil,
        name: String,
        bundleIdentifier: String?,
        applicationName: String,
        type: MenuBarItemType,
        symbolName: String,
        processIdentifier: pid_t,
        isActionable: Bool,
        isAppleProvided: Bool,
        accessibilityFrame: CGRect? = nil,
        visibilityState: MenuBarVisibilityState = .unknown,
        visibilityReason: String = "Not classified",
        interactionKind: InteractionKind = .unsupported,
        discoveryOrder: Int = 0
    ) {
        self.id = id
        self.stableIdentity = stableIdentity
            ?? "\(bundleIdentifier ?? "pid:\(processIdentifier)")::\(name)"
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.type = type
        self.symbolName = symbolName
        self.processIdentifier = processIdentifier
        self.isActionable = isActionable
        self.isAppleProvided = isAppleProvided
        self.accessibilityFrame = accessibilityFrame
        self.visibilityState = visibilityState
        self.visibilityReason = visibilityReason
        self.interactionKind = interactionKind
        self.discoveryOrder = discoveryOrder
    }
}

struct ProxyMenuNode: Identifiable, Sendable {
    enum Kind: Sendable {
        case command
        case separator
    }

    let id: UUID
    let kind: Kind
    let title: String
    let isEnabled: Bool
    let isChecked: Bool
    let keyEquivalent: String
    let keyModifiers: UInt
    let actionID: UUID?
    let children: [ProxyMenuNode]
}

struct ItemInteraction: Sendable {
    let kind: InteractionKind
    let menu: [ProxyMenuNode]
    let externalWindow: ExternalWindowEvidence?

    init(
        kind: InteractionKind,
        menu: [ProxyMenuNode],
        externalWindow: ExternalWindowEvidence? = nil
    ) {
        self.kind = kind
        self.menu = menu
        self.externalWindow = externalWindow
    }
}
