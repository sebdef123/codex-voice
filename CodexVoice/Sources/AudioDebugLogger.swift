import Foundation

enum AudioDebugLogger {
    private static let queue = DispatchQueue(label: "local.codex.voice.audio-debug-logger")
    private static let includeTextKey = "includeSpokenTextInDiagnosticLogs"

    static var includesTextContent: Bool {
        UserDefaults.standard.bool(forKey: includeTextKey)
    }

    static var logURL: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_VOICE_LOG_FILE"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Codex Voice 2", isDirectory: true)
            .appendingPathComponent("voice-events.jsonl")
    }

    static func log(_ event: String, fields: [String: Any] = [:]) {
        queue.async {
            var object = fields
            object["event"] = event
            object["timestamp"] = isoTimestamp()

            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                  var line = String(data: data, encoding: .utf8) else {
                return
            }

            line.append("\n")
            append(line)
        }
    }

    static func setIncludesTextContent(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: includeTextKey)
    }

    static func addTextField(_ text: String, named name: String, to fields: inout [String: Any]) {
        guard includesTextContent else { return }
        fields[name] = text
    }

    static func clearLog() {
        queue.sync {
            truncateLog(at: logURL)
        }
    }

    private static func append(_ line: String) {
        let url = logURL
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    private static func truncateLog(at url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.truncate(atOffset: 0)
    }

    private static func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
