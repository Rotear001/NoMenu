import Foundation

enum MenuBarSymbol {
    static func name(for itemName: String, bundleIdentifier: String?) -> String {
        let key = "\(itemName) \(bundleIdentifier ?? "")".lowercased()

        let mappings: [(tokens: [String], symbol: String)] = [
            (["battery", "power"], "battery.75percent"),
            (["wi-fi", "wifi", "airport"], "wifi"),
            (["bluetooth"], "wave.3.right"),
            (["control center", "controlcenter"], "switch.2"),
            (["spotlight", "search"], "magnifyingglass"),
            (["clock", "date", "time"], "clock"),
            (["input", "keyboard", "language"], "character.textbox"),
            (["sound", "volume", "audio"], "speaker.wave.2.fill"),
            (["screen", "display", "monitor"], "display"),
            (["vpn", "security", "lock"], "lock.shield"),
            (["sync", "drive", "dropbox", "cloud"], "arrow.triangle.2.circlepath"),
            (["chat", "message", "slack", "discord"], "bubble.left.and.bubble.right.fill"),
            (["music", "spotify", "audio"], "music.note"),
            (["weather"], "cloud.sun.fill"),
            (["calendar"], "calendar"),
            (["systemuiserver"], "switch.2")
        ]

        return mappings.first(where: { mapping in
            mapping.tokens.contains(where: key.contains)
        })?.symbol ?? "app.fill"
    }
}
