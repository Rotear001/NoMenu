import AppKit
import SwiftUI

/// Native selection/action semantics inside the existing custom Settings row.
/// Explicit appearance keeps AppKit's title readable in the dark SwiftUI shell.
struct SettingsNativePicker<Option: SettingsPickerOption>: View {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let title: String
    @Binding var selection: Option
    @Binding var openDropdown: String?
    let language: AppLanguage
    var options: [Option] = Array(Option.allCases)
    @Environment(\.noMenuAnimationsEnabled) private var animationsEnabled
    private var expanded: Bool { openDropdown == title }
    private var alternatives: [Option] { options.filter { $0 != selection } }
    private var motion: Animation? { animationsEnabled ? .easeInOut(duration: 0.2) : nil }
    var body: some View {
        VStack(spacing: 0) {
            SettingsPickerHeader(title: title, selection: $selection, options: options,
                                 language: language, expanded: expanded) {
                withAnimation(motion) { openDropdown = expanded ? nil : title }
            }
            .frame(width: controlWidth, height: controlHeight)
            .overlay(alignment: .trailing) {
                DropdownChevron()
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    .frame(width: 5 * scale, height: 2.5 * scale)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .padding(.trailing, 12.5 * scale)
                    .allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                ForEach(alternatives, id: \.self) { option in
                    Button {
                        withAnimation(motion) { selection = option; openDropdown = nil }
                    } label: {
                        Text(option.displayName(language: language))
                            .font(.custom("Helvetica Neue", fixedSize: 8 * scale))
                            .foregroundStyle(Color.white.opacity(0.86))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10 * scale)
                            .frame(width: controlWidth, height: controlHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: expanded ? CGFloat(alternatives.count) * controlHeight : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)
        }
        .frame(width: controlWidth)
        .background(SettingsDesign.Colors.control)
        .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
        .onExitCommand { withAnimation(motion) { openDropdown = nil } }
    }

    private var scale: CGFloat { selectionScale }
    private var selectionScale: CGFloat { InterfaceScaleStore.current }
    private var controlWidth: CGFloat { 120 + 60 * (scale - 1) }
    private var controlHeight: CGFloat { 20 * scale }
}

private struct DropdownChevron: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
    }
}

private struct SettingsPickerHeader<Option: SettingsPickerOption>: NSViewRepresentable {
    @ObservedObject private var interfaceMetrics = InterfaceScaleStore.shared
    let title: String
    @Binding var selection: Option
    var options: [Option] = Array(Option.allCases)
    let language: AppLanguage
    var expanded: Bool
    var onOpen: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let control = SettingsCompactPopUpButton(frame: .zero, pullsDown: false)
        control.appearance = NSAppearance(named: .darkAqua)
        control.isBordered = false
        control.font = NSFont(name: "Helvetica Neue", size: 8 * InterfaceScaleStore.current)
        control.target = context.coordinator
        control.action = #selector(Coordinator.select(_:))
        control.setAccessibilityLabel(title)
        return control
    }
    func updateNSView(_ control: NSPopUpButton, context: Context) {
        if let header = control as? SettingsCompactPopUpButton {
            header.onOpen = onOpen
            header.expanded = expanded
        }
        context.coordinator.selection = $selection
        control.font = NSFont(name: "Helvetica Neue", size: 8 * InterfaceScaleStore.current)
        let titles = options.map { $0.displayName(language: language) }
        if control.itemTitles != titles {
            control.removeAllItems()
            control.addItems(withTitles: titles)
        }
        control.selectItem(at: options.firstIndex(of: selection) ?? 0)
        control.menu?.font = control.font
        control.menu?.minimumWidth = 120 * InterfaceScaleStore.current
        control.needsDisplay = true
    }
    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Option>
        init(selection: Binding<Option>) { self.selection = selection }
        @objc func select(_ sender: NSPopUpButton) {
            guard sender.indexOfSelectedItem >= 0 else { return }
            selection.wrappedValue = Array(Option.allCases)[sender.indexOfSelectedItem]
        }
    }
}

/// Only draws the compact label/chevron; native popup tracking and actions remain intact.
private final class SettingsCompactPopUpButton: NSPopUpButton {
    var onOpen: (() -> Void)?
    var expanded = false
    override func mouseDown(with event: NSEvent) { onOpen?() }
    override func performClick(_ sender: Any?) { onOpen?() }
    override func accessibilityPerformPress() -> Bool { onOpen?(); return true }
    override func keyDown(with event: NSEvent) {
        if [36, 49, 125, 126].contains(event.keyCode) { onOpen?() }
        else if event.keyCode == 53 { if expanded { onOpen?() } }
        else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 8 * InterfaceScaleStore.current),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86)
        ]
        let title = (titleOfSelectedItem ?? "") as NSString
        let height = title.size(withAttributes: attributes).height
        title.draw(in: NSRect(x: 10, y: (bounds.height - height) / 2,
                              width: max(0, bounds.width - 28), height: height),
                   withAttributes: attributes)
    }
}
