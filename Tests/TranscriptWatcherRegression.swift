import Foundation

@main
struct TranscriptWatcherRegression {
    static func main() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-voice-transcript-watcher-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let userFile = root.appendingPathComponent("user.jsonl")
        let subagentFile = root.appendingPathComponent("subagent.jsonl")
        write(sessionMeta, to: userFile)
        write(subagentMeta, to: subagentFile)

        var events: [TranscriptEvent] = []
        let watcher = TranscriptWatcher(sessionsRoot: root, pollingInterval: 0.02)
        watcher.onEvent = { events.append($0) }
        watcher.start()

        let commentary = agentMessage("phrase ecrite en deux morceaux")
        let splitPoint = commentary.index(commentary.startIndex, offsetBy: commentary.count / 2)
        append(String(commentary[..<splitPoint]), to: userFile)
        runLoop(for: 0.15)
        expect(events.isEmpty, "partial JSONL line must not emit an event")

        append(String(commentary[splitPoint...]) + "\n", to: userFile)
        waitFor("completed commentary") {
            events.contains { event in
                if case .commentary(let message) = event { return message == "phrase ecrite en deux morceaux" }
                return false
            }
        }

        append(agentMessage("subagent message") + "\n", to: subagentFile)
        runLoop(for: 0.15)
        expect(!events.contains { event in
            if case .commentary(let message) = event { return message == "subagent message" }
            return false
        }, "subagent transcript must be ignored")

        let completed = taskComplete("turn-1", message: "final once")
        append(completed + "\n" + completed + "\n", to: userFile)
        waitFor("completed final") {
            events.contains { event in
                if case .taskComplete(let message, _) = event { return message == "final once" }
                return false
            }
        }
        let finalCount = events.reduce(into: 0) { count, event in
            if case .taskComplete(let message, _) = event, message == "final once" { count += 1 }
        }
        expect(finalCount == 1, "duplicate completed turn must be emitted once")

        watcher.stop()
        print("TranscriptWatcherRegression: ok")
    }

    private static let sessionMeta = """
    {"type":"session_meta","payload":{"thread_source":"user"}}
    """

    private static let subagentMeta = """
    {"type":"session_meta","payload":{"source":{"subagent":true}}}
    """

    private static func agentMessage(_ message: String) -> String {
        """
        {"type":"event_msg","payload":{"type":"agent_message","phase":"commentary","message":"\(message)"}}
        """
    }

    private static func taskComplete(_ turnID: String, message: String) -> String {
        """
        {"type":"event_msg","payload":{"type":"task_complete","turn_id":"\(turnID)","last_agent_message":"\(message)"}}
        """
    }

    private static func write(_ text: String, to url: URL) {
        try? text.appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func append(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8), let handle = try? FileHandle(forWritingTo: url) else {
            fail("unable to append transcript fixture")
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static func waitFor(_ name: String, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if condition() { return }
            runLoop(for: 0.02)
        }
        fail("timed out waiting for \(name)")
    }

    private static func runLoop(for interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("TranscriptWatcherRegression: \(message)\n", stderr)
        exit(1)
    }
}
