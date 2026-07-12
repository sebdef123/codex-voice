import Foundation

@main
struct AudioDebugLoggerRegression {
    static func main() {
        let rawText = String(repeating: "x", count: 12_500)
        AudioDebugLogger.setIncludesTextContent(false)
        var privateFields: [String: Any] = ["rawLength": rawText.count]
        AudioDebugLogger.addTextField(rawText, named: "raw", to: &privateFields)
        AudioDebugLogger.log("private_message_regression", fields: privateFields)

        waitForLog(containing: "private_message_regression")
        guard let privateLog = try? String(contentsOf: AudioDebugLogger.logURL, encoding: .utf8),
              !privateLog.contains(rawText), privateLog.contains("rawLength") else {
            fail("AudioDebugLoggerRegression: private text was recorded")
        }

        AudioDebugLogger.setIncludesTextContent(true)
        var diagnosticFields: [String: Any] = ["rawLength": rawText.count]
        AudioDebugLogger.addTextField(rawText, named: "raw", to: &diagnosticFields)
        AudioDebugLogger.log("diagnostic_message_regression", fields: diagnosticFields)

        waitForLog(containing: rawText)
        guard let diagnosticLog = try? String(contentsOf: AudioDebugLogger.logURL, encoding: .utf8), diagnosticLog.contains(rawText) else {
            fail("AudioDebugLoggerRegression: diagnostic text was not recorded")
        }

        AudioDebugLogger.clearLog()
        guard let clearedLog = try? String(contentsOf: AudioDebugLogger.logURL, encoding: .utf8), clearedLog.isEmpty else {
            fail("AudioDebugLoggerRegression: log was not cleared")
        }
        AudioDebugLogger.setIncludesTextContent(false)
        print("AudioDebugLoggerRegression: ok")
    }

    private static func waitForLog(containing expected: String) {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let text = try? String(contentsOf: AudioDebugLogger.logURL, encoding: .utf8), text.contains(expected) {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}
