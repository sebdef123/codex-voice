import Foundation

final class VoxtralServerManager {
    private let queue = DispatchQueue(label: "local.codex.voice2.voxtral-server")
    private let healthURL = URL(string: "http://127.0.0.1:8765/health")!
    private var process: Process?
    private var outputPipe: Pipe?
    private var waiters: [(Result<Void, Error>) -> Void] = []
    private var isStarting = false
    private var ownsServer = false
    private let logURL: URL

    var onStateChange: ((VoxtralServerState) -> Void)?

    init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Codex Voice 2", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appendingPathComponent("voxtral-server.log")
    }

    func ensureRunning(completion: @escaping (Result<Void, Error>) -> Void) {
        checkHealth { [weak self] healthy in
            guard let self else { return }
            self.queue.async {
                if healthy {
                    if self.process?.isRunning != true { self.ownsServer = false }
                    self.publish(.ready)
                    DispatchQueue.main.async { completion(.success(())) }
                    return
                }
                self.waiters.append(completion)
                guard !self.isStarting else { return }
                self.isStarting = true
                self.publish(.starting)
                self.launchBundledServer()
                self.waitForHealth(attempt: 0)
            }
        }
    }

    func stopIfOwned() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.ownsServer, let process = self.process, process.isRunning else {
                self.publish(.stopped)
                return
            }
            self.isStarting = false
            self.appendServerLog("server_stop_requested owner=CodexVoice2\n".data(using: .utf8)!)
            process.terminate()
        }
    }

    func clearLog() {
        queue.sync {
            guard FileManager.default.fileExists(atPath: logURL.path),
                  let handle = try? FileHandle(forWritingTo: logURL) else { return }
            defer { try? handle.close() }
            try? handle.truncate(atOffset: 0)
        }
    }

    private func launchBundledServer() {
        guard process?.isRunning != true else { return }
        guard let resourceURL = Bundle.main.resourceURL else {
            finish(.failure(VoiceOutputError.unavailable("Le launcher Voxtral est introuvable dans l'application.")))
            return
        }
        let script = resourceURL.appendingPathComponent("Scripts/start-voxtral-server.sh")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            finish(.failure(VoiceOutputError.unavailable("Le launcher Voxtral est indisponible: \(script.path)")))
            return
        }

        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        newProcess.arguments = [script.path, "--preload"]
        newProcess.currentDirectoryURL = script.deletingLastPathComponent()
        let pipe = Pipe()
        newProcess.standardOutput = pipe
        newProcess.standardError = pipe
        outputPipe = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.appendServerLog(data)
        }
        newProcess.terminationHandler = { [weak self] process in
            self?.appendServerLog("server_exit status=\(process.terminationStatus)\n".data(using: .utf8)!)
            self?.queue.async {
                guard let self else { return }
                self.process = nil
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self.outputPipe = nil
                self.ownsServer = false
                if self.isStarting {
                    self.finish(.failure(VoiceOutputError.unavailable("Le serveur Voxtral s'est arrete pendant le demarrage.")))
                } else {
                    self.publish(.stopped)
                }
            }
        }
        do {
            try newProcess.run()
            process = newProcess
            ownsServer = true
            appendServerLog("server_launch preload=true owner=CodexVoice2\n".data(using: .utf8)!)
        } catch {
            finish(.failure(error))
        }
    }

    private func waitForHealth(attempt: Int) {
        checkHealth { [weak self] healthy in
            guard let self else { return }
            self.queue.async {
                guard self.isStarting else { return }
                if healthy {
                    self.finish(.success(()))
                } else if attempt >= 360 {
                    self.finish(.failure(VoiceOutputError.unavailable("Voxtral n'est pas pret apres 3 minutes. Consulte voxtral-server.log.")))
                } else {
                    self.queue.asyncAfter(deadline: .now() + 0.5) { self.waitForHealth(attempt: attempt + 1) }
                }
            }
        }
    }

    private func checkHealth(completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 1
        URLSession.shared.dataTask(with: request) { _, response, _ in
            completion((response as? HTTPURLResponse)?.statusCode == 200)
        }.resume()
    }

    private func finish(_ result: Result<Void, Error>) {
        let waiters = self.waiters
        self.waiters.removeAll()
        isStarting = false
        switch result {
        case .success: publish(.ready)
        case .failure: publish(.unavailable)
        }
        DispatchQueue.main.async { waiters.forEach { $0(result) } }
    }

    private func publish(_ state: VoxtralServerState) {
        DispatchQueue.main.async { self.onStateChange?(state) }
    }

    private func appendServerLog(_ data: Data) {
        queue.async { [logURL] in
            if FileManager.default.fileExists(atPath: logURL.path), let handle = try? FileHandle(forWritingTo: logURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
