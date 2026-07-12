import Foundation

private func waitFor<T>(timeout: TimeInterval, _ operation: (@escaping (T) -> Void) -> Void) -> T? {
    var value: T?
    operation { value = $0 }

    let deadline = Date().addingTimeInterval(timeout)
    while value == nil, Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return value
}

private func healthIsAvailable() -> Bool {
    guard let url = URL(string: "http://127.0.0.1:8765/health") else { return false }
    let healthy: Bool? = waitFor(timeout: 2) { completion in
        URLSession.shared.dataTask(with: url) { _, response, _ in
            completion((response as? HTTPURLResponse)?.statusCode == 200)
        }.resume()
    }
    return healthy == true
}

@main
struct VoxtralServerManagerAttachRegression {
    static func main() {
        guard healthIsAvailable() else {
            fputs("VoxtralServerManagerAttachRegression: skipped (no external Voxtral server)\n", stderr)
            return
        }

        let manager = VoxtralServerManager()
        let result: Result<Void, Error>? = waitFor(timeout: 3) { completion in
            manager.ensureRunning(completion: completion)
        }

        guard case .success? = result else {
            fputs("VoxtralServerManagerAttachRegression: failed to attach to healthy server\n", stderr)
            exit(1)
        }

        manager.stopIfOwned()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        guard healthIsAvailable() else {
            fputs("VoxtralServerManagerAttachRegression: attached server was stopped\n", stderr)
            exit(1)
        }

        print("VoxtralServerManagerAttachRegression: ok")
    }
}
