import AppKit

/// Scope Escape to this NoMenu-owned window; native full-screen chrome is unchanged.
final class SettingsWindow: NSWindow {
    var closeWithEscape: (() -> Bool)?
    override func cancelOperation(_ sender: Any?) {
        if styleMask.contains(.fullScreen) {
            super.cancelOperation(sender)
            return
        }
        guard closeWithEscape?() == true else { return }
        performClose(sender)
    }
}
