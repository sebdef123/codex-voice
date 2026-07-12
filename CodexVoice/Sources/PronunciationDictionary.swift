import Foundation

enum PronunciationDictionary {
    enum TransferError: LocalizedError {
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Le fichier doit contenir l'entete source,replacement."
            }
        }
    }

    private static let fileName = "pronunciations.csv"

    static var userFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codex Voice 2", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static var activeFileURL: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_VOICE_PRONUNCIATION_FILE"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return userFileURL
    }

    @discardableResult
    static func ensureUserFileExists() -> URL {
        let destination = userFileURL
        guard !FileManager.default.fileExists(atPath: destination.path) else { return destination }

        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let template = Bundle.main.url(forResource: "pronunciations", withExtension: "csv", subdirectory: "Pronunciation") {
            try? FileManager.default.copyItem(at: template, to: destination)
        } else {
            try? "source,replacement\n".write(to: destination, atomically: true, encoding: .utf8)
        }
        return destination
    }

    static func applyForMacOSVoice(to text: String) -> String {
        var output = text
        for (word, replacement) in entries().sorted(by: { $0.key.count > $1.key.count }) {
            output = replaceWholeWord(word, with: replacement, in: output)
        }
        return output
    }

    static func importUserFile(from sourceURL: URL) throws {
        let content = try String(contentsOf: sourceURL, encoding: .utf8)
        guard content.components(separatedBy: .newlines).contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "source,replacement"
        }) else {
            throw TransferError.invalidFormat
        }

        let destination = userFileURL
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: destination, atomically: true, encoding: .utf8)
    }

    private static func entries() -> [String: String] {
        let url = activeFileURL
        if ProcessInfo.processInfo.environment["CODEX_VOICE_PRONUNCIATION_FILE"] == nil {
            _ = ensureUserFileExists()
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        var entries: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let cells = trimmed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            guard cells.count == 2 else { continue }

            let source = cells[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let replacement = cells[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard source != "source", !source.isEmpty, !replacement.isEmpty else { continue }
            entries[source] = replacement
        }
        return entries
    }

    private static func replaceWholeWord(_ word: String, with replacement: String, in text: String) -> String {
        let pattern = #"(?<![\p{L}\p{N}_])\#(NSRegularExpression.escapedPattern(for: word))(?![\p{L}\p{N}_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        var output = text
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range).reversed()

        for match in matches {
            guard let matchRange = Range(match.range, in: output) else { continue }
            let matchedWord = String(output[matchRange])
            output.replaceSubrange(matchRange, with: replacement.matchingCapitalization(of: matchedWord))
        }
        return output
    }
}

private extension String {
    func matchingCapitalization(of source: String) -> String {
        guard let first = source.first, first.isUppercase else { return self }
        guard let replacementFirst = self.first else { return self }
        return replacementFirst.uppercased() + dropFirst()
    }
}
