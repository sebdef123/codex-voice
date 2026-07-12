import Foundation

@main
struct PronunciationDictionaryTransferRegression {
    static func main() {
        let temporaryFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-voice-dictionary-import-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: temporaryFile) }

        let importedContent = "source,replacement\nopen,oh-pen\n"
        try? importedContent.write(to: temporaryFile, atomically: true, encoding: .utf8)

        do {
            try PronunciationDictionary.importUserFile(from: temporaryFile)
        } catch {
            fail("valid dictionary import failed: \(error.localizedDescription)")
        }

        guard let installed = try? String(contentsOf: PronunciationDictionary.userFileURL, encoding: .utf8), installed == importedContent else {
            fail("imported dictionary did not replace the user file")
        }

        let invalidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-voice-dictionary-invalid-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: invalidFile) }
        try? "open,oh-pen\n".write(to: invalidFile, atomically: true, encoding: .utf8)

        do {
            try PronunciationDictionary.importUserFile(from: invalidFile)
            fail("invalid dictionary format was accepted")
        } catch {
            print("PronunciationDictionaryTransferRegression: ok")
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("PronunciationDictionaryTransferRegression: \(message)\n", stderr)
        exit(1)
    }
}
