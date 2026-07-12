import Foundation

enum AppStrings {
    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }

    static func preferredLocalization(for preferredLanguages: [String]) -> String {
        Bundle.preferredLocalizations(
            from: ["fr", "en"],
            forPreferences: preferredLanguages
        ).first == "fr" ? "fr" : "en"
    }
}
