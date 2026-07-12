import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Localization regression failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct LocalizationRegression {
    static func main() throws {
        let expectedLanguages: [([String], String)] = [
            (["fr-FR"], "fr"),
            (["fr-CA", "en-US"], "fr"),
            (["en-GB"], "en"),
            (["de-DE"], "en")
        ]

        for (preferredLanguages, expectedLanguage) in expectedLanguages {
            require(
                AppStrings.preferredLocalization(for: preferredLanguages) == expectedLanguage,
                "\(preferredLanguages) should resolve to \(expectedLanguage)"
            )
        }

        guard let root = ProcessInfo.processInfo.environment["CODEX_VOICE_SOURCE_ROOT"] else {
            fputs("CODEX_VOICE_SOURCE_ROOT is required\n", stderr)
            exit(1)
        }

        for language in ["en", "fr"] {
            let path = "\(root)/CodexVoice/Resources/\(language).lproj/Localizable.strings"
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            for key in ["menu.automaticReading", "menu.voice", "status.monitoringActive", "alert.clearAudioLogsTitle"] {
                require(contents.contains("\"\(key)\""), "\(language) is missing \(key)")
            }
        }

        print("Localization regression: ok")
    }
}
