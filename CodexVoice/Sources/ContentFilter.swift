import Foundation

enum ContentFilter {
    struct PreparedSpeech {
        let text: String
        let omittedCodeBlocks: Int
        let omittedTechnicalLines: Int
    }

    static func prepareForSpeech(_ markdown: String) -> String {
        prepareDetailedForSpeech(markdown).text
    }

    static func prepareDetailedForSpeech(_ markdown: String) -> PreparedSpeech {
        guard !looksLikeMachineReadableStatus(markdown) else {
            return PreparedSpeech(text: "", omittedCodeBlocks: 0, omittedTechnicalLines: 1)
        }

        var text = summarizeFencedCode(in: markdown)
        text = stripInlineCode(in: text)
        text = stripMarkdownSyntax(in: text)
        let filtered = filterTechnicalLines(in: text, includeOmissionNote: true)
        text = collapseWhitespace(in: filtered.text)
        return PreparedSpeech(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            omittedCodeBlocks: filtered.omittedCodeBlocks,
            omittedTechnicalLines: filtered.omittedTechnicalLines
        )
    }

    static func prepareForCommentary(_ markdown: String) -> String? {
        prepareDetailedForCommentary(markdown)?.text
    }

    static func prepareDetailedForCommentary(_ markdown: String) -> PreparedSpeech? {
        var text = summarizeFencedCode(in: markdown)
        text = stripInlineCode(in: text)
        text = stripMarkdownSyntax(in: text)
        let filtered = filterTechnicalLines(in: text, includeOmissionNote: false)
        text = collapseWhitespace(in: filtered.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }
        guard text.count <= 240 else { return nil }
        guard !looksLikeToolOrLogStatus(text) else { return nil }

        return PreparedSpeech(
            text: text,
            omittedCodeBlocks: filtered.omittedCodeBlocks,
            omittedTechnicalLines: filtered.omittedTechnicalLines
        )
    }

    private static func summarizeFencedCode(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var insideFence = false
        var fenceLanguage = ""
        var codeLineCount = 0

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if insideFence {
                    result.append(codeBlockMarker(language: fenceLanguage, lines: codeLineCount))
                    insideFence = false
                    fenceLanguage = ""
                    codeLineCount = 0
                } else {
                    insideFence = true
                    fenceLanguage = line.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "```", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    codeLineCount = 0
                }
                continue
            }

            if insideFence {
                codeLineCount += 1
            } else {
                result.append(line)
            }
        }

        if insideFence {
            result.append(codeBlockMarker(language: fenceLanguage, lines: codeLineCount))
        }

        return result.joined(separator: "\n")
    }

    private static func codeBlockMarker(language: String, lines: Int) -> String {
        let safeLanguage = language.isEmpty ? "code" : language
        return "[[CODE_BLOCK:\(safeLanguage):\(lines)]]"
    }

    private static func stripInlineCode(in text: String) -> String {
        text.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
    }

    private static func stripMarkdownSyntax(in text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: #"(?m)^\s{0,3}#{1,6}\s*"#, with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(?m)^\s*>\s?"#, with: "Citation. ", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(?m)^\s*[-*]\s+"#, with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(?m)^\s*\d+\.\s+"#, with: "", options: .regularExpression)
        return output
    }

    private static func filterTechnicalLines(in text: String, includeOmissionNote: Bool) -> PreparedSpeech {
        var omittedCodeBlocks = 0
        var omittedTechnicalLines = 0
        var totalOmittedCodeBlocks = 0
        var totalOmittedTechnicalLines = 0
        var spokenLines: [String] = []

        func flushOmissionsIfNeeded() {
            guard includeOmissionNote else {
                omittedCodeBlocks = 0
                omittedTechnicalLines = 0
                return
            }

            if let note = omissionNote(codeBlocks: omittedCodeBlocks, technicalLines: omittedTechnicalLines) {
                spokenLines.append(note)
            }
            omittedCodeBlocks = 0
            omittedTechnicalLines = 0
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                flushOmissionsIfNeeded()
                spokenLines.append(line)
                continue
            }

            if trimmed.hasPrefix("[[CODE_BLOCK:") {
                omittedCodeBlocks += 1
                totalOmittedCodeBlocks += 1
                continue
            }

            if shouldOmitSkillMarker(trimmed) || shouldOmitTechnicalLine(trimmed) {
                omittedTechnicalLines += 1
                totalOmittedTechnicalLines += 1
                continue
            }

            flushOmissionsIfNeeded()
            spokenLines.append(line)
        }

        flushOmissionsIfNeeded()

        return PreparedSpeech(
            text: spokenLines.joined(separator: "\n"),
            omittedCodeBlocks: totalOmittedCodeBlocks,
            omittedTechnicalLines: totalOmittedTechnicalLines
        )
    }

    private static func shouldOmitSkillMarker(_ line: String) -> Bool {
        let normalized = line.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let pattern = #"^skills?\s+(?:used|utilise(?:e)?)\s*:"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }

    private static func shouldOmitTechnicalLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()

        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return true
        }

        if line.count > 180 && technicalScore(line) >= 2 {
            return true
        }

        if line.count > 120 && technicalScore(line) >= 3 {
            return true
        }

        return false
    }

    private static func technicalScore(_ line: String) -> Int {
        let lowercased = line.lowercased()
        let tokens = [
            "/", "{", "}", "=", "->", "::", "$", "|", "\\",
            ".swift", ".py", ".json", ".js", ".ts", ".md",
            "node_modules", "/users/", "library/", "contents/",
            "error:", "warning:", "traceback", "exception",
            "git diff", "@@", "```"
        ]

        return tokens.reduce(0) { score, token in
            score + (lowercased.contains(token) ? 1 : 0)
        }
    }

    private static func omissionNote(codeBlocks: Int, technicalLines: Int) -> String? {
        guard codeBlocks > 0 || technicalLines >= 3 else { return nil }

        switch (codeBlocks, technicalLines) {
        case (1, 0..<3):
            return "Bloc de code ignoré."
        case (let blocks, 0..<3):
            return "\(blocks) blocs de code ignorés."
        case (0, _):
            return "Quelques details techniques ont ete omis."
        case (1, _):
            return "Bloc de code ignoré, avec quelques details techniques omis."
        default:
            return "\(codeBlocks) blocs de code ignorés, avec quelques details techniques omis."
        }
    }

    private static func looksLikeToolOrLogStatus(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if looksLikeMachineReadableStatus(text) {
            return true
        }

        if technicalScore(text) >= 2 {
            return true
        }

        let noisyPhrases = [
            "exec_command",
            "apply_patch",
            "tool call",
            "session id",
            "chunk id",
            "wall time",
            "exit code",
            "risk_level",
            "user_authorization",
            "stderr",
            "stdout"
        ]

        return noisyPhrases.contains { lowercased.contains($0) }
    }

    private static func looksLikeMachineReadableStatus(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let technicalKeys = [
                "outcome",
                "risk_level",
                "user_authorization",
                "rationale"
            ]
            return object.keys.contains { technicalKeys.contains($0) }
        }

        let lowercased = trimmed.lowercased()
        return lowercased.hasPrefix("\"outcome\"")
            || lowercased.hasPrefix("outcome:")
            || lowercased.hasPrefix("risk_level:")
            || lowercased.hasPrefix("user_authorization:")
    }

    private static func collapseWhitespace(in text: String) -> String {
        text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
    }
}
