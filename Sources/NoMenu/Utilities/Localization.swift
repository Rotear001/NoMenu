import Foundation

enum L10n {
    nonisolated(unsafe) static var resourceBundleOverride: Bundle?

    static func text(_ key: String) -> String {
        text(key, language: LocalizationStore.current)
    }
    static func text(_ key: String, language: AppLanguage) -> String {
        let resources = resourceBundleOverride ?? Bundle.main
        guard let path = resources.path(forResource: language.localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

enum LocalizationStore {
    nonisolated(unsafe) static var current: AppLanguage = .systemDefault
}

extension String {
    func localized(_ language: AppLanguage) -> String { L10n.text(self, language: language) }
}
