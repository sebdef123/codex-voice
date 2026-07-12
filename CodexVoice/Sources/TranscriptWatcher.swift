import Foundation

enum TranscriptEvent {
    case taskStarted
    case userMessage
    case commentary(String)
    case taskComplete(String, String?)
    case foundLatest(String)
    case watchError(String)
}

struct AssistantHistoryItem {
    let kind: String
    let message: String
}

final class TranscriptWatcher {
    static let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex")
        .appendingPathComponent("sessions")

    var onEvent: ((TranscriptEvent) -> Void)?
    var isEnabled = true

    private var timer: Timer?
    private var offsets: [URL: UInt64] = [:]
    private var pendingLineData: [URL: Data] = [:]
    private var userThreadByFile: [URL: Bool] = [:]
    private var seenCompletedTurnIDs = Set<String>()
    private var commentaryPolicy = CommentaryDeliveryPolicy()
    private let queue = DispatchQueue(label: "local.codex.voice.transcript-watcher")
    private let sessionsRoot: URL
    private let pollingInterval: TimeInterval

    init(sessionsRoot: URL = TranscriptWatcher.sessionsRoot, pollingInterval: TimeInterval = 1.0) {
        self.sessionsRoot = sessionsRoot
        self.pollingInterval = pollingInterval
    }

    func start() {
        guard timer == nil else { return }
        primeExistingFiles()
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.scanForUpdates()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func latestCompletedMessage() -> String? {
        let files = userTranscriptFiles().sorted { lhs, rhs in
            (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast >
            (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }

        for file in files {
            guard let lines = try? String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines).reversed() else {
                continue
            }

            for line in lines where !line.isEmpty {
                guard let event = CodexTranscriptLine.parse(line), case .taskComplete(let message, _) = event else {
                    continue
                }
                return message
            }
        }

        return nil
    }

    func assistantHistory() -> [AssistantHistoryItem] {
        guard let file = latestTranscriptFile(),
              let content = try? String(contentsOf: file, encoding: .utf8) else {
            return []
        }

        var items: [AssistantHistoryItem] = []
        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            guard let event = CodexTranscriptLine.parse(line) else { continue }
            switch event {
            case .commentary(let message):
                appendHistoryItem(kind: "commentary", message: message, to: &items)
            case .taskComplete(let message, _):
                appendHistoryItem(kind: "final", message: message, to: &items)
            case .taskStarted, .userMessage, .foundLatest, .watchError:
                continue
            }
        }

        return items
    }

    private func primeExistingFiles() {
        for file in transcriptFiles() {
            _ = isUserTranscript(file)
            offsets[file] = fileSize(file)
        }
    }

    private func scanForUpdates() {
        queue.async { [weak self] in
            guard let self else { return }

            let files = self.transcriptFiles()
            if files.isEmpty {
                DispatchQueue.main.async {
                    self.onEvent?(.watchError(AppStrings.text("status.noTranscriptFound")))
                }
                return
            }

            self.pruneState(keeping: Set(files))
            for file in files {
                self.readNewLines(from: file)
            }
        }
    }

    private func readNewLines(from file: URL) {
        let previousOffset = offsets[file] ?? 0
        let currentSize = fileSize(file)

        guard isUserTranscript(file) else {
            offsets[file] = currentSize
            pendingLineData[file] = nil
            return
        }

        if currentSize < previousOffset {
            offsets[file] = 0
            pendingLineData[file] = nil
        }

        guard currentSize > (offsets[file] ?? 0) else { return }

        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }

            try handle.seek(toOffset: offsets[file] ?? 0)
            let data = try handle.readToEnd() ?? Data()
            offsets[file] = currentSize

            var buffered = pendingLineData[file] ?? Data()
            buffered.append(data)
            while let newlineIndex = buffered.firstIndex(of: 0x0A) {
                let lineData = buffered.prefix(upTo: newlineIndex)
                buffered.removeSubrange(...newlineIndex)
                guard let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .newlines), !line.isEmpty else {
                    continue
                }
                guard let event = CodexTranscriptLine.parse(line) else { continue }
                emit(event)
            }
            pendingLineData[file] = buffered
        } catch {
            DispatchQueue.main.async {
                self.onEvent?(.watchError(AppStrings.text("status.transcriptReadError")))
            }
        }
    }

    private func emit(_ event: TranscriptEvent) {
        guard isEnabled || shouldEmitWhenDisabled(event) else { return }

        switch event {
        case .taskStarted, .userMessage:
            commentaryPolicy.reset()
        case .commentary:
            switch commentaryPolicy.decision() {
            case .emit:
                break
            case .cooldown:
                AudioDebugLogger.log("commentary_suppressed", fields: ["reason": "cooldown"])
                return
            case .limitReached:
                AudioDebugLogger.log("commentary_suppressed", fields: ["reason": "turn_limit"])
                return
            }
        case .taskComplete(_, let turnID):
            if let turnID {
                guard !seenCompletedTurnIDs.contains(turnID) else { return }
                seenCompletedTurnIDs.insert(turnID)
            }
        case .foundLatest, .watchError:
            break
        }

        DispatchQueue.main.async {
            self.onEvent?(event)
        }
    }

    private func shouldEmitWhenDisabled(_ event: TranscriptEvent) -> Bool {
        switch event {
        case .taskStarted, .userMessage, .watchError:
            return true
        case .commentary, .taskComplete, .foundLatest:
            return false
        }
    }

    private func transcriptFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            return url
        }
    }

    private func userTranscriptFiles() -> [URL] {
        transcriptFiles().filter(isUserTranscript)
    }

    private func latestTranscriptFile() -> URL? {
        userTranscriptFiles().max { lhs, rhs in
            modificationDate(lhs) < modificationDate(rhs)
        }
    }

    private func isUserTranscript(_ url: URL) -> Bool {
        if let isUserThread = userThreadByFile[url] {
            return isUserThread
        }

        let isUserThread = readSessionMetadata(from: url)
        userThreadByFile[url] = isUserThread
        return isUserThread
    }

    private func readSessionMetadata(from url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 32 * 1024),
              let text = String(data: header, encoding: .utf8) else {
            return true
        }

        for line in text.components(separatedBy: .newlines).prefix(12) where !line.isEmpty {
            guard let metadata = CodexTranscriptLine.sessionMetadata(line) else { continue }
            return metadata.isUserThread
        }

        return true
    }

    private func pruneState(keeping files: Set<URL>) {
        offsets = offsets.filter { files.contains($0.key) }
        pendingLineData = pendingLineData.filter { files.contains($0.key) }
        userThreadByFile = userThreadByFile.filter { files.contains($0.key) }
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func fileSize(_ url: URL) -> UInt64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
    }

    private func appendHistoryItem(kind: String, message: String, to items: inout [AssistantHistoryItem]) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if items.last?.message.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
            return
        }

        items.append(AssistantHistoryItem(kind: kind, message: trimmed))
    }
}

private enum CodexTranscriptLine {
    struct SessionMetadata {
        let isUserThread: Bool
    }

    static func sessionMetadata(_ line: String) -> SessionMetadata? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String,
              type == "session_meta",
              let payload = object["payload"] as? [String: Any] else {
            return nil
        }

        let threadSource = (payload["thread_source"] as? String)?.lowercased()
        if threadSource == "subagent" {
            return SessionMetadata(isUserThread: false)
        }

        if let source = payload["source"] as? [String: Any], source["subagent"] != nil {
            return SessionMetadata(isUserThread: false)
        }

        let instructions = ((payload["base_instructions"] as? [String: Any])?["text"] as? String)?.lowercased() ?? ""
        if instructions.contains("you are judging one planned coding-agent action") {
            return SessionMetadata(isUserThread: false)
        }

        return SessionMetadata(isUserThread: true)
    }

    static func parse(_ line: String) -> TranscriptEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return nil
        }

        if type == "event_msg",
           let payload = object["payload"] as? [String: Any],
            let payloadType = payload["type"] as? String {
            switch payloadType {
            case "task_started":
                return .taskStarted
            case "user_message":
                return .userMessage
            case "agent_message":
                guard let phase = payload["phase"] as? String,
                      phase == "commentary",
                      let message = payload["message"] as? String,
                      !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return .commentary(message)
            case "task_complete":
                let turnID = payload["turn_id"] as? String
                if let message = payload["last_agent_message"] as? String {
                    return .taskComplete(message, turnID)
                }
            default:
                return nil
            }
        }

        return nil
    }
}
