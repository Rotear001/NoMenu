import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// The single backdrop-filter layer used by the NoMenu bar. `backgroundFilters`
/// is the public macOS Core Animation API for filtering pixels behind a layer;
/// no screen capture or stacked NSVisualEffectView is involved. The constant
/// material tint is identical for every blur level, while the user-controlled
/// transparency tint remains a separate SwiftUI layer above this view.
struct NoMenuBackgroundVisualEffect: NSViewRepresentable {
    let blur: NoMenuBackgroundBlur

    func makeNSView(context: Context) -> NoMenuBackdropFilterView {
        let view = NoMenuBackdropFilterView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NoMenuBackdropFilterView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NoMenuBackdropFilterView) {
        view.setBlurRadius(blur.radius)
    }
}

private extension NoMenuBackgroundBlur {
    var radius: Float? {
        switch self {
        case .off: nil
        case .low: 5
        case .medium: 14
        case .high: 28
        }
    }
}

final class NoMenuBackdropFilterView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.40).cgColor
        layer?.allowsGroupOpacity = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setBlurRadius(_ radius: Float?) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let radius {
            let filter = CIFilter.gaussianBlur()
            filter.radius = radius
            layer.backgroundFilters = [filter]
        } else {
            // No residual material/filter remains active in the Off state.
            layer.backgroundFilters = nil
        }
        CATransaction.commit()
    }
}
