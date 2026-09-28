import Foundation
import CoreGraphics

func checkMenuBarCompatibility() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let bar = CGRect(x: 0, y: 0, width: 1512, height: 37)
    let window = CGRect(x: 0, y: 0, width: 1512, height: 33)
    let extras = CGRect(x: 888, y: 0, width: 604, height: 33)
    func validates(_ bounds: CGRect, layer: Int = 24, owner: Bool = true,
                   ax: CGRect? = nil, display: CGRect? = nil) -> Bool {
        MenuBarCompatibility.validatesFullWidthMenuBar(
            window: bounds, layer: layer, nativeOwner: owner,
            screen: display ?? screen, menuBar: bar, extras: ax ?? extras
        )
    }
    assert(validates(window), "Observed macOS 27 native bar must survive the legacy width limit")
    assert(!validates(window, owner: false), "An unrelated full-width owner is not menu-bar evidence")
    assert(!validates(window, layer: 20))
    assert(!validates(window, layer: 27))
    assert(!validates(screen), "A screen-sized overlay is not a menu bar")
    assert(!validates(CGRect(x: 0, y: 100, width: 1512, height: 33)))
    assert(!validates(CGRect(x: 436, y: 0, width: 640, height: 210)),
           "The observed NoNoTcH overlay must remain rejected")
    assert(!validates(CGRect(x: 0, y: 0, width: 1400, height: 33)))
    assert(!validates(window, ax: CGRect(x: 888, y: 103, width: 604, height: 33)))
    assert(!validates(window, display: CGRect(x: 1512, y: 103, width: 1135, height: 789)))
    assert(MenuBarCompatibility.validatesFullWidthMenuBar(
        window: CGRect(x: 1512, y: 103, width: 1135, height: 30), layer: 24, nativeOwner: true,
        screen: CGRect(x: 1512, y: 103, width: 1135, height: 789),
        menuBar: CGRect(x: 1512, y: 103, width: 1135, height: 28),
        extras: CGRect(x: 1980, y: 103, width: 647, height: 30)),
        "Observed 30pt external bar may exceed the derived 28pt band by 2pt")
    print("PASS: full-width native environment, unrelated owners/layers/overlays/displays rejected")

    let boundary = CGRect(x: 887, y: 1, width: 17.5, height: 30)
    assert(MenuBarCompatibility.isOverflowBoundary(button: boundary, extras: extras))
    assert(!MenuBarCompatibility.isOverflowBoundary(
        button: CGRect(x: 1320, y: 5.5, width: 26, height: 22), extras: extras))
    // Exact public AX frames recorded before, during and after manual expansion.
    let collapsed = [CGRect(x: 871, y: 4.5, width: 34, height: 24),
                     CGRect(x: 873, y: 4.5, width: 24, height: 24),
                     CGRect(x: 855, y: -0.5, width: 50, height: 34)]
    let expanded = [CGRect(x: 610, y: 4.5, width: 34, height: 24),
                    CGRect(x: 580, y: 4.5, width: 24, height: 24),
                    CGRect(x: 524, y: -0.5, width: 50, height: 34)]
    for frame in collapsed + expanded + collapsed {
        assert(MenuBarCompatibility.belongsToNativeOverflow(frame: frame, boundary: boundary))
    }
    for frame in [CGRect(x: 911, y: 4.5, width: 34, height: 24),
                  CGRect(x: 1015, y: 4.5, width: 56, height: 24),
                  CGRect(x: 1208, y: 5.5, width: 22, height: 22)] {
        assert(!MenuBarCompatibility.belongsToNativeOverflow(frame: frame, boundary: boundary))
    }
    print("PASS: collapsed/expanded/collapsed overflow set preserved; visible third-party/system items excluded")
}

checkMenuBarCompatibility()
