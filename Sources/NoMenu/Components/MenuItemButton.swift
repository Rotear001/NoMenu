import AppKit
import OSLog
import SwiftUI

struct MenuItemButton: NSViewRepresentable {
    let item: MenuBarItem
    let icon: NSImage?
    @ObservedObject var artwork: LiveArtworkImage
    let isSelected: Bool
    let hoverHighlightEnabled: Bool
    @ObservedObject var service: MenuBarService

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item, service: service)
    }

    func makeNSView(context: Context) -> OverflowItemNSButton {
        let button = OverflowItemNSButton(frame: NSRect(x: 0, y: 0, width: 38, height: 28))
        button.target = context.coordinator
        button.action = #selector(Coordinator.activate(_:))
        update(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: OverflowItemNSButton, context: Context) {
        if context.coordinator.item.id != item.id {
            button.clearTransientState()
        }
        context.coordinator.item = item
        update(button, coordinator: context.coordinator)
    }

    private func update(_ button: OverflowItemNSButton, coordinator: Coordinator) {
        // Route actions from the concrete hit-tested button. Coordinators can
        // survive SwiftUI moves when the recent-item order changes.
        // NSViewRepresentable may also hand an existing NSButton to a newly
        // current coordinator. Refresh target/action together with the
        // represented item so the visible button and its action owner can
        // never describe different menu-bar items.
        button.target = coordinator
        button.action = #selector(Coordinator.activate(_:))
        button.representedItem = item
        let live = service.settings.preferences.iconAppearance == .appIcon ? nil : artwork.image
        let source = live ?? icon ?? NSImage(systemSymbolName: item.symbolName, accessibilityDescription: item.name)
        let image = source?.copy() as? NSImage
        let barSize = service.settings.preferences.barSize
        image?.size = NSSize(width: barSize.iconSize, height: barSize.iconSize)
        button.image = image
        button.renderedItemStableIdentity = item.stableIdentity
        button.renderedArtworkOwnerIdentity = String(describing: ObjectIdentifier(artwork))
        button.renderedImageSource = live != nil ? "live" : (icon != nil ? "cached" : "symbol")
        // Optional names use the existing mouse tracking only. Clear tooltip
        // state on exit, press, selection changes and represented-item reuse;
        // never replace the app's actual interaction with a help bubble.
        button.hoverName = service.settings.preferences.showItemNames ? item.name : nil
        button.itemWidth = max(
            24,
            service.settings.preferences.iconSpacing.itemWidth + barSize.itemWidthAdjustment
        )
        button.setAccessibilityLabel(item.name)
        button.hoverHighlightEnabled = hoverHighlightEnabled
        button.isSelected = isSelected
    }

    @MainActor
    final class Coordinator: NSObject {
        var item: MenuBarItem
        private let service: MenuBarService
        private let logger = Logger(subsystem: "com.nomenu.utility", category: "Interaction")
        private weak var anchorButton: NSButton?
        private var currentMenu: NSMenu?
        private var interactionTask: Task<Void, Never>?
        private var menuSwitchMonitor: Any?
        private var menuSwitchEventTap: CFMachPort?
        private var menuSwitchRunLoopSource: CFRunLoopSource?
        private weak var pendingSwitchButton: OverflowItemNSButton?
        private var pendingSwitchItem: MenuBarItem?
        private var currentMenuOwner: (item: MenuBarItem, sessionID: UUID, eventID: UUID)?
        private let monitorOwnerID = UUID()

        init(item: MenuBarItem, service: MenuBarService) {
            self.item = item
            self.service = service
        }

        var displayRegressionProxyOwnerDescription: String {
            guard let owner = currentMenuOwner else { return "none" }
            return "\(owner.item.id.uuidString)/\(owner.item.stableIdentity)/\(owner.sessionID.uuidString)"
        }

        @objc func activate(_ sender: NSButton) {
            activate(sender, requestedItemOverride: nil)
        }

        private func activate(
            _ sender: NSButton,
            requestedItemOverride: MenuBarItem?
        ) {
            let senderItem = (sender as? OverflowItemNSButton)?.representedItem
            // The concrete hit-tested button (or the immutable direct-switch
            // snapshot) is the only activation source of truth. `item` is
            // SwiftUI update state and must never be a routing fallback.
            guard let requestedItem = requestedItemOverride ?? senderItem else {
                logger.error(
                    "[NoMenuRoutingOwnership] rejected activation without a concrete button item; button=\(String(describing: ObjectIdentifier(sender)), privacy: .public) coordinatorItem=\(self.item.stableIdentity, privacy: .public)"
                )
                return
            }
            let eventID = UUID()
            let activeBefore = service.selectedItem?.id
            let sameActiveItem = activeBefore == requestedItem.id
            logger.notice(
                "[NoMenuRoutingOwnership] eventID=\(eventID.uuidString, privacy: .public) stage=click physicalClickedItem=\(senderItem?.stableIdentity ?? requestedItem.stableIdentity, privacy: .public) buttonStableID=\(senderItem?.stableIdentity ?? "none", privacy: .public) previousActiveItem=\(self.service.selectedItem?.stableIdentity ?? "none", privacy: .public) actionTargetItem=\(requestedItem.stableIdentity, privacy: .public) expectedTarget=\(requestedItem.stableIdentity, privacy: .public) coordinatorItem=\(self.item.stableIdentity, privacy: .public)"
            )
            if let button = sender as? OverflowItemNSButton {
                logger.notice(
                    "[NoMenuRoutingGeometry] eventID=\(eventID.uuidString, privacy: .public) stage=action-entry modelOrder=[\(self.service.overflowItems.map(\.stableIdentity).joined(separator: " | "), privacy: .public)] \(button.diagnosticRoutingSnapshot(at: button.currentEventScreenPoint), privacy: .public)"
                )
            }
            MenuBarClickDiagnostics.record("overflow-button-action", event: NSApp.currentEvent,
                                           detail: "requestedItem=\(requestedItem.id) stableIdentity=\(requestedItem.stableIdentity) senderItem=\(senderItem?.id.uuidString ?? "none") senderStableIdentity=\(senderItem?.stableIdentity ?? "none") button=\(ObjectIdentifier(sender)) selectedItem=\(service.selectedItem?.id.uuidString ?? "none") proxyOwner=\(currentMenuOwner?.item.id.uuidString ?? "none") proxyOpen=\(currentMenu != nil)")
            logger.debug(
                "[NoMenuItemRoutingDebug] clickedItemID=\(requestedItem.id.uuidString, privacy: .public) clickedStableIdentity=\(requestedItem.stableIdentity, privacy: .public) senderItemID=\(senderItem?.id.uuidString ?? "none", privacy: .public) activeItemID=\(activeBefore?.uuidString ?? "none", privacy: .public) proxyOwnerID=\(self.currentMenuOwner?.item.id.uuidString ?? "none", privacy: .public) sameItem=\(sameActiveItem, privacy: .public) beforeProxyOpen=\(self.currentMenu != nil, privacy: .public)"
            )
            (sender as? OverflowItemNSButton)?.clearTransientState()
            if service.toggleOffInteractionIfActive(for: requestedItem) {
                interactionTask?.cancel()
                let menu = currentMenu
                currentMenu = nil
                (sender as? OverflowItemNSButton)?.isSelected = false
                menu?.cancelTrackingWithoutAnimation()
                logger.debug(
                    "[NoMenuActiveToggleDebug] finalAction=toggleOff afterProxyOpen=\(self.currentMenu != nil, privacy: .public) selectedItem=\(self.service.selectedItem?.id.uuidString ?? "none", privacy: .public)"
                )
                return
            }

            anchorButton = sender
            let sessionID = service.beginInteraction(for: requestedItem)
            logger.notice(
                "[NoMenuRoutingOwnership] eventID=\(eventID.uuidString, privacy: .public) stage=session-began proxySessionID=\(sessionID.uuidString, privacy: .public) currentActiveItem=\(self.service.selectedItem?.stableIdentity ?? "none", privacy: .public) actionTargetItem=\(requestedItem.stableIdentity, privacy: .public) expectedTarget=\(requestedItem.stableIdentity, privacy: .public)"
            )
            interactionTask = Task { @MainActor [weak self, weak sender] in
                guard let self, let sender else { return }
                let interaction = await service.interaction(
                    for: requestedItem,
                    routingEventID: eventID,
                    sessionID: sessionID
                )
                guard !Task.isCancelled,
                      service.isInteractionCurrent(for: requestedItem.id, sessionID: sessionID),
                      sender.window != nil else {
                    logger.notice(
                        "[NoMenuRoutingOwnership] eventID=\(eventID.uuidString, privacy: .public) stage=stale-result-rejected proxySessionID=\(sessionID.uuidString, privacy: .public) actionTargetItem=\(requestedItem.stableIdentity, privacy: .public) currentActiveItem=\(self.service.selectedItem?.stableIdentity ?? "none", privacy: .public)"
                    )
                    return
                }

                switch interaction.kind {
                case .customPopover:
                    interactionTask = nil
                    guard let window = interaction.externalWindow else {
                        service.endInteraction(for: requestedItem.id, sessionID: sessionID)
                        return
                    }
                    service.retainExternalInteraction(
                        for: requestedItem,
                        sessionID: sessionID,
                        window: window
                    )
                    service.activationCompleted(for: requestedItem)
                    logger.notice(
                        "[NoMenuRoutingOwnership] eventID=\(eventID.uuidString, privacy: .public) stage=final-open proxySessionID=\(sessionID.uuidString, privacy: .public) proxyOwnerItem=\(requestedItem.stableIdentity, privacy: .public) actionTargetItem=\(requestedItem.stableIdentity, privacy: .public) expectedTarget=\(requestedItem.stableIdentity, privacy: .public) actualFinalTarget=\(requestedItem.stableIdentity, privacy: .public) kind=customPopover"
                    )
                    return
                case .directPress:
                    interactionTask = nil
                    service.endInteraction(for: requestedItem.id, sessionID: sessionID)
                    service.activationCompleted(for: requestedItem)
                    return
                case .unsupported, .launchOnly:
                    interactionTask = nil
                    logger.notice(
                        "[\(requestedItem.name, privacy: .public)] interaction unsupported; no fallback popup presented"
                    )
                    service.endInteraction(for: requestedItem.id, sessionID: sessionID)
                    return
                case .menuTree:
                    break
                }

                let menu = makeMenu(for: interaction, item: requestedItem)
                currentMenu = menu
                currentMenuOwner = (requestedItem, sessionID, eventID)
                logger.notice(
                    "[NoMenuRoutingOwnership] eventID=\(eventID.uuidString, privacy: .public) stage=proxy-created proxySessionID=\(sessionID.uuidString, privacy: .public) proxyOwnerItem=\(requestedItem.stableIdentity, privacy: .public) actionTargetItem=\(requestedItem.stableIdentity, privacy: .public) expectedTarget=\(requestedItem.stableIdentity, privacy: .public) actualFinalTarget=\(requestedItem.stableIdentity, privacy: .public) kind=menuTree"
                )
                guard let placement = popupPlacement(for: menu, below: sender) else {
                    currentMenu = nil
                    currentMenuOwner = nil
                    service.endInteraction(for: requestedItem.id, sessionID: sessionID)
                    return
                }

                pendingSwitchButton = nil
                pendingSwitchItem = nil
                installMenuSwitchMonitor(menu: menu, currentButton: sender)
                menu.popUp(
                    positioning: nil,
                    at: placement,
                    in: nil
                )
                // Native menu tracking can consume the physical mouse-up that
                // normally releases NSButtonCell's highlight. End that AppKit
                // press lifecycle before publishing/logging the closed state.
                (sender as? OverflowItemNSButton)?.clearTransientState()
                logger.debug(
                    "[NoMenuInputPathDebug] stage=menu-close-callback itemID=\(requestedItem.id.uuidString, privacy: .public) proxyOpen=\(self.currentMenu != nil, privacy: .public) selectedItem=\(self.service.selectedItem?.id.uuidString ?? "none", privacy: .public) button={\((sender as? OverflowItemNSButton)?.diagnosticInteractionState ?? "unavailable", privacy: .public)}"
                )
                if let button = sender as? OverflowItemNSButton {
                    logger.notice(
                        "[NoMenuRoutingGeometry] eventID=\(eventID.uuidString, privacy: .public) stage=menu-return modelOrder=[\(self.service.overflowItems.map(\.stableIdentity).joined(separator: " | "), privacy: .public)] \(button.diagnosticRoutingSnapshot(at: NSEvent.mouseLocation), privacy: .public)"
                    )
                }
                guard currentMenuOwner?.sessionID == sessionID else { return }
                removeMenuSwitchMonitor()
                currentMenu = nil
                currentMenuOwner = nil
                service.endInteraction(for: requestedItem.id, sessionID: sessionID)

                let switchButton = pendingSwitchButton
                let switchItem = pendingSwitchItem
                pendingSwitchButton = nil
                pendingSwitchItem = nil
                interactionTask = nil
                guard let switchButton,
                      let switchItem,
                      switchButton !== sender,
                      switchButton.window != nil,
                      let coordinator = switchButton.target as? Coordinator else { return }
                logger.notice(
                    "[NoMenuRoutingOwnership] eventID=\(eventID.uuidString, privacy: .public) stage=switch-dispatch previousActiveItem=\(requestedItem.stableIdentity, privacy: .public) physicalClickedItem=\(switchButton.representedItem?.stableIdentity ?? "none", privacy: .public) buttonStableID=\(switchButton.representedItem?.stableIdentity ?? "none", privacy: .public) actionTargetItem=\(switchItem.stableIdentity, privacy: .public) expectedTarget=\(switchItem.stableIdentity, privacy: .public) destinationCoordinatorItem=\(coordinator.item.stableIdentity, privacy: .public)"
                )
                coordinator.activate(switchButton, requestedItemOverride: switchItem)
            }
        }

        private func installMenuSwitchMonitor(menu: NSMenu, currentButton: NSButton) {
            removeMenuSwitchMonitor()
            let eventMask = CGEventMask(1) << CGEventType.leftMouseDown.rawValue
            menuSwitchEventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { _, type, event, userInfo in
                    guard type == .leftMouseDown, let userInfo else {
                        return Unmanaged.passUnretained(event)
                    }
                    let coordinator = Unmanaged<Coordinator>
                        .fromOpaque(userInfo)
                        .takeUnretainedValue()
                    let consumed = coordinator.handleMenuSwitchMouseDown(at: event.location)
                    if Thread.isMainThread {
                        MenuBarClickDiagnostics.record("menu-switch-event-tap",
                            point: coordinator.appKitScreenPoint(from: event.location), consumed: consumed,
                            detail: "cgEventTime=\(event.timestamp) proxyOpen=\(coordinator.currentMenu != nil)")
                    }
                    if consumed {
                        return nil
                    }
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            if let menuSwitchEventTap {
                let source = CFMachPortCreateRunLoopSource(nil, menuSwitchEventTap, 0)
                menuSwitchRunLoopSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: menuSwitchEventTap, enable: true)
                logger.debug("installed overflow menu-switch event tap")
            } else {
                logger.error("could not install overflow menu-switch event tap; retaining local fallback")
            }

            // Retain a local monitor as a fallback for environments where the
            // session event tap is unavailable. Events consumed by the event tap
            // never reach this monitor, so the two paths cannot double-switch.
            menuSwitchMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
                [weak self, weak menu, weak currentButton] event in
                guard let self, let menu, let currentButton,
                      let clickedButton = overflowButton(at: event),
                      handleMenuSwitchClick(
                        clickedButton,
                        menu: menu,
                        currentButton: currentButton,
                        screenPoint: event.window?.convertPoint(toScreen: event.locationInWindow)
                      ) else {
                    MenuBarClickDiagnostics.record("menu-switch-local-monitor", event: event, consumed: false)
                    return event
                }
                MenuBarClickDiagnostics.record("menu-switch-local-monitor", event: event, consumed: true)
                return nil
            }
            service.reportInteractionMonitors(owner: monitorOwnerID,
                count: (menuSwitchMonitor == nil ? 0 : 1) + (menuSwitchEventTap == nil ? 0 : 1))
        }

        private func removeMenuSwitchMonitor() {
            service.reportInteractionMonitors(owner: monitorOwnerID, count: 0)
            if let menuSwitchMonitor {
                NSEvent.removeMonitor(menuSwitchMonitor)
                self.menuSwitchMonitor = nil
            }
            if let menuSwitchRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), menuSwitchRunLoopSource, .commonModes)
                self.menuSwitchRunLoopSource = nil
            }
            if let menuSwitchEventTap {
                CGEvent.tapEnable(tap: menuSwitchEventTap, enable: false)
                CFMachPortInvalidate(menuSwitchEventTap)
                self.menuSwitchEventTap = nil
            }
        }

        private func handleMenuSwitchMouseDown(
            at eventPoint: CGPoint
        ) -> Bool {
            guard Thread.isMainThread,
                  let menu = currentMenu,
                  let currentButton = anchorButton,
                  let screenPoint = appKitScreenPoint(from: eventPoint),
                  let clickedButton = overflowButton(at: screenPoint) else { return false }
            return handleMenuSwitchClick(
                clickedButton,
                menu: menu,
                currentButton: currentButton,
                screenPoint: screenPoint
            )
        }

        private func handleMenuSwitchClick(
            _ clickedButton: OverflowItemNSButton,
            menu: NSMenu,
            currentButton: NSButton,
            screenPoint: NSPoint?
        ) -> Bool {
            guard let menuOwner = currentMenuOwner?.item,
                  let clickedItem = clickedButton.representedItem else { return false }
            (currentButton as? OverflowItemNSButton)?.clearTransientState()
            clickedButton.clearTransientState()
            let sameActiveItem = clickedItem.id == menuOwner.id
            pendingSwitchButton = sameActiveItem ? nil : clickedButton
            pendingSwitchItem = sameActiveItem ? nil : clickedItem
            logger.notice(
                "[NoMenuRoutingOwnership] eventID=\(self.currentMenuOwner?.eventID.uuidString ?? "none", privacy: .public) stage=switch-captured physicalClickedItem=\(clickedItem.stableIdentity, privacy: .public) buttonStableID=\(clickedButton.representedItem?.stableIdentity ?? "none", privacy: .public) previousActiveItem=\(menuOwner.stableIdentity, privacy: .public) currentActiveItem=\(self.service.selectedItem?.stableIdentity ?? "none", privacy: .public) proxySessionID=\(self.currentMenuOwner?.sessionID.uuidString ?? "none", privacy: .public) proxyOwnerItem=\(menuOwner.stableIdentity, privacy: .public) actionTargetItem=\(clickedItem.stableIdentity, privacy: .public) expectedTarget=\(clickedItem.stableIdentity, privacy: .public)"
            )
            logger.notice(
                "[NoMenuRoutingGeometry] eventID=\(self.currentMenuOwner?.eventID.uuidString ?? "none", privacy: .public) stage=switch-hit modelOrder=[\(self.service.overflowItems.map(\.stableIdentity).joined(separator: " | "), privacy: .public)] \(clickedButton.diagnosticRoutingSnapshot(at: screenPoint ?? NSEvent.mouseLocation), privacy: .public)"
            )
            let destination = sameActiveItem
                ? "closed"
                : clickedItem.name
            logger.debug(
                "[NoMenuItemRoutingDebug] clickedItemID=\(clickedItem.id.uuidString, privacy: .public) clickedStableIdentity=\(clickedItem.stableIdentity, privacy: .public) proxyOwnerID=\(menuOwner.id.uuidString, privacy: .public) proxyOwnerStableIdentity=\(menuOwner.stableIdentity, privacy: .public) activeItemID=\(self.service.selectedItem?.id.uuidString ?? "none", privacy: .public) sameItem=\(sameActiveItem, privacy: .public) beforeProxyOpen=\(self.currentMenu != nil, privacy: .public) beforeButton={\(clickedButton.diagnosticInteractionState, privacy: .public)}"
            )
            if sameActiveItem {
                // Native NSMenu tracking intercepts this physical click before the
                // underlying NSButton action. Clear both the model and the actual
                // button layer now; do not wait for menu.popUp to unwind.
                interactionTask?.cancel()
                _ = service.toggleOffInteractionIfActive(for: menuOwner)
                currentMenu = nil
                clickedButton.isSelected = false
            } else {
                // Direct switching keeps the old owner from remaining visually
                // selected while the next coordinator starts its interaction.
                (currentButton as? OverflowItemNSButton)?.isSelected = false
            }
            logger.notice(
                "switching overflow interaction from \(menuOwner.name, privacy: .public) to \(destination, privacy: .public)"
            )
            menu.cancelTrackingWithoutAnimation()
            logger.debug(
                "[NoMenuActiveToggleDebug] finalAction=\(sameActiveItem ? "toggleOff" : "switchItem", privacy: .public) afterProxyOpen=\(self.currentMenu != nil, privacy: .public) selectedItem=\(self.service.selectedItem?.id.uuidString ?? "none", privacy: .public) afterButton={\(clickedButton.diagnosticInteractionState, privacy: .public)}"
            )
            return true
        }

        private func appKitScreenPoint(from eventPoint: CGPoint) -> NSPoint? {
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                        as? NSNumber else { continue }
                let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
                guard displayBounds.contains(eventPoint) else { continue }
                return NSPoint(
                    x: screen.frame.minX + eventPoint.x - displayBounds.minX,
                    y: screen.frame.maxY - (eventPoint.y - displayBounds.minY)
                )
            }
            return nil
        }

        private func overflowButton(at event: NSEvent) -> OverflowItemNSButton? {
            let screenPoint = event.window?.convertPoint(toScreen: event.locationInWindow)
                ?? NSEvent.mouseLocation
            return overflowButton(at: screenPoint)
        }

        private func overflowButton(at screenPoint: NSPoint) -> OverflowItemNSButton? {
            for window in NSApp.windows where window.isVisible {
                guard let contentView = window.contentView,
                      window.frame.contains(screenPoint) else { continue }
                let windowPoint = window.convertPoint(fromScreen: screenPoint)
                let contentPoint = contentView.convert(windowPoint, from: nil)
                var candidate = contentView.hitTest(contentPoint)
                while let view = candidate {
                    if let button = view as? OverflowItemNSButton { return button }
                    candidate = view.superview
                }
            }
            return nil
        }

        private func popupPlacement(
            for menu: NSMenu,
            below button: NSButton
        ) -> NSPoint? {
            guard let window = button.window,
                  let screen = window.screen ?? NSScreen.screens.first(where: {
                      $0.frame.intersects(window.frame)
                  }) else { return nil }

            // Resolve the SwiftUI-hosted NSButton through one explicit conversion
            // chain. From this point onward all geometry is in AppKit screen
            // coordinates, whose origin is at the lower-left of the display.
            let localFrame = button.bounds
            let windowFrame = button.convert(localFrame, to: nil)
            let screenFrame = window.convertToScreen(windowFrame)

            menu.update()
            let menuSize = menu.size
            let screenBounds = screen.visibleFrame
            let screenInset = 8.0
            let verticalGap = 6.0

            var originX = screenFrame.midX - (menuSize.width / 2)
            let minimumX = screenBounds.minX + screenInset
            let maximumX = screenBounds.maxX - screenInset - menuSize.width
            if maximumX >= minimumX {
                originX = min(max(originX, minimumX), maximumX)
            } else {
                originX = screenBounds.minX
            }

            // NSMenu positions its top edge at this point. Since screen coordinates
            // increase upward, subtracting from the clicked frame's lower edge
            // places the entire menu below NoMenu without crossing the panel.
            var originY = screenFrame.minY - verticalGap
            let minimumTopY = screenBounds.minY + screenInset + menuSize.height
            if originY < minimumTopY {
                originY = minimumTopY
            }

            let origin = NSPoint(x: originX, y: originY)
            logger.notice(
                "[\(self.item.name, privacy: .public)] clicked local frame=\(String(describing: localFrame), privacy: .public); window frame=\(String(describing: windowFrame), privacy: .public); converted screen frame=\(String(describing: screenFrame), privacy: .public); menu size=\(String(describing: menuSize), privacy: .public); visible screen=\(String(describing: screenBounds), privacy: .public); final popup origin=\(String(describing: origin), privacy: .public)"
            )
            return origin
        }

        private func makeMenu(for interaction: ItemInteraction, item: MenuBarItem) -> NSMenu {
            let menu = NSMenu(title: item.name)
            menu.autoenablesItems = false
            switch interaction.kind {
            case .menuTree where !interaction.menu.isEmpty:
                append(interaction.menu, to: menu)
            case .unsupported, .menuTree, .customPopover, .directPress, .launchOnly:
                let unavailable = NSMenuItem(
                    title: L10n.text("Interaction unavailable", language: service.settings.preferences.language),
                    action: nil,
                    keyEquivalent: ""
                )
                unavailable.isEnabled = false
                menu.addItem(unavailable)
            }
            return menu
        }

        private func append(_ nodes: [ProxyMenuNode], to menu: NSMenu) {
            for node in nodes {
                if node.kind == .separator {
                    menu.addItem(.separator())
                    continue
                }
                let menuItem = NSMenuItem(
                    title: node.title,
                    action: node.actionID == nil ? nil : #selector(performProxyAction(_:)),
                    keyEquivalent: node.keyEquivalent.lowercased()
                )
                menuItem.target = self
                menuItem.isEnabled = node.isEnabled
                menuItem.state = node.isChecked ? .on : .off
                menuItem.keyEquivalentModifierMask = modifierFlags(from: node.keyModifiers)
                menuItem.representedObject = node.actionID?.uuidString
                if !node.children.isEmpty {
                    let submenu = NSMenu(title: node.title)
                    submenu.autoenablesItems = false
                    append(node.children, to: submenu)
                    menuItem.submenu = submenu
                }
                menu.addItem(menuItem)
            }
        }

        private func modifierFlags(from rawValue: UInt) -> NSEvent.ModifierFlags {
            var result: NSEvent.ModifierFlags = []
            if rawValue & 1 != 0 { result.insert(.shift) }
            if rawValue & 2 != 0 { result.insert(.option) }
            if rawValue & 4 != 0 { result.insert(.control) }
            if rawValue & 8 == 0 { result.insert(.command) }
            return result
        }

        @objc private func performProxyAction(_ sender: NSMenuItem) {
            guard let value = sender.representedObject as? String,
                  let actionID = UUID(uuidString: value) else { return }
            service.performMenuAction(actionID)
        }

    }
}

@MainActor
final class OverflowItemNSButton: NSButton {
    var representedItem: MenuBarItem?
    var renderedItemStableIdentity = "none"
    var renderedArtworkOwnerIdentity = "none"
    var renderedImageSource = "none"
    var itemWidth: CGFloat = 38 {
        didSet { if itemWidth != oldValue { invalidateIntrinsicContentSize() } }
    }
    var hoverName: String? {
        didSet { if hoverName != oldValue { toolTip = nil } }
    }
    var hoverHighlightEnabled = true {
        didSet {
            if !hoverHighlightEnabled { isHovered = false }
            applySelectionLayer()
        }
    }
    var isSelected = false {
        didSet {
            if oldValue && !isSelected {
                clearTransientState()
            } else {
                applySelectionLayer()
            }
        }
    }
    private var isHovered = false {
        didSet { applySelectionLayer() }
    }
    private var isPressed = false {
        didSet { applySelectionLayer() }
    }
    private var hoverTrackingArea: NSTrackingArea?
    private let routingLogger = Logger(subsystem: "com.nomenu.utility", category: "Interaction")

    var diagnosticInteractionState: String {
        "selected=\(isSelected) pressed=\(isPressed) highlighted=\(isHovered) cellHighlighted=\(cell?.isHighlighted ?? false)"
    }

    var currentEventScreenPoint: NSPoint {
        guard let event = NSApp.currentEvent else { return NSEvent.mouseLocation }
        return event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    func diagnosticRoutingSnapshot(at screenPoint: NSPoint) -> String {
        let targetIdentity = target.map { String(describing: ObjectIdentifier($0)) } ?? "none"
        let coordinatorItem = (target as? MenuItemButton.Coordinator)?.item.stableIdentity ?? "none"
        let actionName = action.map(NSStringFromSelector) ?? "none"
        let ownFrame = diagnosticScreenFrame
        let clipDescription: String
        if let clip = enclosingScrollView?.contentView {
            clipDescription = "bounds=\(Self.compactRect(clip.bounds)) frame=\(Self.compactRect(clip.frame))"
        } else {
            clipDescription = "none"
        }
        let buttonOrder = Self.descendants(of: window?.contentView)
            .compactMap { $0 as? OverflowItemNSButton }
            .sorted {
                let lhs = $0.diagnosticScreenFrame
                let rhs = $1.diagnosticScreenFrame
                return lhs.minX == rhs.minX ? lhs.minY < rhs.minY : lhs.minX < rhs.minX
            }
            .map { button in
                let targetItem = (button.target as? MenuItemButton.Coordinator)?.item.stableIdentity ?? "none"
                return "{object=\(ObjectIdentifier(button)) frame=\(Self.compactRect(button.diagnosticScreenFrame)) represented=\(button.representedItem?.stableIdentity ?? "none") rendered=\(button.renderedItemStableIdentity) source=\(button.renderedImageSource) artwork=\(button.renderedArtworkOwnerIdentity) coordinator=\(targetItem) selected=\(button.isSelected)}"
            }
            .joined(separator: " ; ")
        return "point=\(Self.compactPoint(screenPoint)) hitObject=\(ObjectIdentifier(self)) hitFrame=\(Self.compactRect(ownFrame)) pointInsideHitFrame=\(ownFrame.contains(screenPoint)) represented=\(representedItem?.stableIdentity ?? "none") rendered=\(renderedItemStableIdentity) imageSource=\(renderedImageSource) artworkOwner=\(renderedArtworkOwnerIdentity) target=\(targetIdentity) coordinator=\(coordinatorItem) action=\(actionName) scrollClip={\(clipDescription)} visualOrder=[\(buttonOrder)]"
    }

    private var diagnosticScreenFrame: NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    private static func descendants(of root: NSView?) -> [NSView] {
        guard let root else { return [] }
        return [root] + root.subviews.flatMap { descendants(of: $0) }
    }

    private static func compactPoint(_ point: NSPoint) -> String {
        String(format: "(%.1f,%.1f)", point.x, point.y)
    }

    private static func compactRect(_ rect: NSRect) -> String {
        String(format: "(%.1f,%.1f,%.1f,%.1f)", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 14
        setButtonType(.momentaryChange)
        // OverflowItemNSButton owns its pressed/selected visuals. Prevent the
        // backing cell from independently tinting the image while highlighted.
        (cell as? NSButtonCell)?.highlightsBy = []
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: itemWidth, height: 28)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func highlight(_ flag: Bool) {
        MenuBarClickDiagnostics.record(
            "overflow-button-highlight-before",
            event: NSApp.currentEvent,
            detail: "requested=\(flag) button={\(diagnosticInteractionState)}"
        )
        isPressed = flag
        MenuBarClickDiagnostics.record(
            "overflow-button-highlight-after",
            event: NSApp.currentEvent,
            detail: "requested=\(flag) button={\(diagnosticInteractionState)}"
        )
    }

    override func mouseDown(with event: NSEvent) {
        let screenPoint = event.window?.convertPoint(toScreen: event.locationInWindow)
            ?? NSEvent.mouseLocation
        routingLogger.notice(
            "[NoMenuRoutingGeometry] stage=physical-mouseDown \(self.diagnosticRoutingSnapshot(at: screenPoint), privacy: .public)"
        )
        // A direct switch is initiated while NSMenu owns a nested tracking
        // loop. Its mouse-down is intentionally consumed by the switch event
        // tap, so AppKit can occasionally deliver the first later mouse-down
        // to the button that owned the pre-menu click. The event location is
        // authoritative here: only correct a proven out-of-frame delivery,
        // then dispatch exactly once from the button actually under it.
        if !diagnosticScreenFrame.contains(screenPoint),
           let hitButton = Self.overflowButton(at: screenPoint, in: window),
           hitButton !== self {
            routingLogger.notice(
                "[NoMenuRoutingGeometry] stage=stale-mouse-owner-corrected staleObject=\(String(describing: ObjectIdentifier(self)), privacy: .public) staleItem=\(self.representedItem?.stableIdentity ?? "none", privacy: .public) actualObject=\(String(describing: ObjectIdentifier(hitButton)), privacy: .public) actualItem=\(hitButton.representedItem?.stableIdentity ?? "none", privacy: .public) point=\(Self.compactPoint(screenPoint), privacy: .public)"
            )
            clearTransientState()
            hitButton.dispatchMouseDownAction()
            return
        }
        MenuBarClickDiagnostics.recordFirstPostDisplayChangeClickIfNeeded(
            button: self,
            item: representedItem,
            event: event
        )
        MenuBarClickDiagnostics.record(
            "overflow-button-mouseDown-enter",
            event: event,
            detail: "button={\(diagnosticInteractionState)}"
        )
        // Dispatch exactly once on mouse-down without entering NSButton's
        // synchronous tracking loop. A proxy NSMenu runs its own nested event
        // loop; combining the two loops can leave this mouseDown invocation
        // alive long enough to absorb the next Tap-to-Click gesture.
        dispatchMouseDownAction()
        MenuBarClickDiagnostics.record(
            "overflow-button-mouseDown-return",
            event: NSApp.currentEvent,
            detail: "button={\(diagnosticInteractionState)}"
        )
    }

    override func mouseUp(with event: NSEvent) {
        MenuBarClickDiagnostics.record(
            "overflow-button-mouseUp-enter",
            event: event,
            detail: "button={\(diagnosticInteractionState)}"
        )
        // mouseDown owns dispatch, so mouseUp only terminates transient input
        // state. Calling NSButton here would introduce a second action path.
        isPressed = false
        releaseAppKitHighlight()
        MenuBarClickDiagnostics.record(
            "overflow-button-mouseUp-return",
            event: NSApp.currentEvent,
            detail: "button={\(diagnosticInteractionState)}"
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard roundedHitPath.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        toolTip = nil
        isHovered = false
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(for: event)
    }

    private var roundedHitPath: NSBezierPath {
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
    }

    private func dispatchMouseDownAction() {
        isPressed = true
        if let action {
            _ = NSApp.sendAction(action, to: target, from: self)
        }
        isPressed = false
        releaseAppKitHighlight()
    }

    private static func overflowButton(at screenPoint: NSPoint, in window: NSWindow?) -> OverflowItemNSButton? {
        guard let window, window.frame.contains(screenPoint) else { return nil }
        return descendants(of: window.contentView)
            .compactMap { $0 as? OverflowItemNSButton }
            .first { button in
                guard button.window === window,
                      button.diagnosticScreenFrame.contains(screenPoint) else { return false }
                let windowPoint = window.convertPoint(fromScreen: screenPoint)
                let localPoint = button.convert(windowPoint, from: nil)
                return button.roundedHitPath.contains(localPoint)
            }
    }

    private func updateHover(for event: NSEvent) {
        isHovered = roundedHitPath.contains(convert(event.locationInWindow, from: nil))
        toolTip = isHovered && !isSelected && !isPressed ? hoverName : nil
    }

    func clearTransientState() {
        toolTip = nil
        isHovered = false
        isPressed = false
        releaseAppKitHighlight()
        applySelectionLayer()
    }

    /// NSMenu tracking may take ownership of mouse-up, so NSButton's backing
    /// cell cannot always finish its normal highlight cycle by itself.
    private func releaseAppKitHighlight() {
        guard cell?.isHighlighted == true else { return }
        cell?.isHighlighted = false
        needsDisplay = true
    }

    private func applySelectionLayer() {
        let color: NSColor
        if isSelected {
            color = NSColor.white.withAlphaComponent(0.24)
        } else if isPressed {
            color = NSColor.white.withAlphaComponent(0.10)
        } else if hoverHighlightEnabled && isHovered {
            color = NSColor.white.withAlphaComponent(0.035)
        } else {
            color = .clear
        }
        layer?.backgroundColor = color.cgColor
    }
}
