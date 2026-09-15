import AppKit
import Combine

MainActor.assumeIsolated {
    let options = LiveArtworkFrameRate.allCases.map(\.framesPerSecond)
    assert(options == [5, 10, 15, 30])
    assert(SettingsPreferences().liveArtworkFrameRate == .ten)
    var preferences = SettingsPreferences()
    preferences.rememberLastPage = true
    preferences.liveArtworkFrameRate = .thirty
    let encoded = try! JSONEncoder().encode(preferences)
    assert(try! JSONDecoder().decode(SettingsPreferences.self, from: encoded).liveArtworkFrameRate == .thirty)
    var legacy = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    legacy.removeValue(forKey: "storedLiveArtworkFrameRate")
    let migrated = try! JSONDecoder().decode(SettingsPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
    assert(migrated.liveArtworkFrameRate == .ten && migrated.rememberLastPage)
    print("PASS: four FPS options, default 10, persistence and legacy preferences preserved")

    let artwork = LiveArtworkImage()
    var redraws = 0
    let subscription = artwork.$image.dropFirst().sink { _ in redraws += 1 }
    let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    let first = context.makeImage()!
    artwork.accept(first)
    artwork.accept(first)
    assert(redraws == 1)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    artwork.accept(context.makeImage()!)
    assert(redraws == 2)
    subscription.cancel()
    print("PASS: identical frames do not publish; changed artwork publishes once")
}
