import Foundation

@main
struct VoxtralCancellationRegression {
    static func main() {
        guard healthIsAvailable() else {
            fputs("VoxtralCancellationRegression: skipped (no external Voxtral server)\n", stderr)
            return
        }

        let speaker = VoiceOutputController()
        var callbacks = 0
        speaker.onFirstAudio = { callbacks += 1 }
        speaker.onFinish = { callbacks += 1 }
        speaker.onError = { _ in callbacks += 1 }

        speaker.selectEngine(.voxtralStreaming)
        speaker.speak("This request must be cancelled before playback starts.", sourceKind: "test", rawText: "This request must be cancelled before playback starts.")

        guard speaker.isSpeaking else {
            fputs("VoxtralCancellationRegression: request was not registered\n", stderr)
            exit(1)
        }

        speaker.stop(reason: "test_cancel_before_ready")
        guard !speaker.isSpeaking else {
            fputs("VoxtralCancellationRegression: request remained active after stop\n", stderr)
            exit(1)
        }

        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        guard callbacks == 0 else {
            fputs("VoxtralCancellationRegression: cancelled request emitted a late callback\n", stderr)
            exit(1)
        }

        print("VoxtralCancellationRegression: ok")
    }

    private static func healthIsAvailable() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8765/health") else { return false }
        var available: Bool?
        URLSession.shared.dataTask(with: url) { _, response, _ in
            available = (response as? HTTPURLResponse)?.statusCode == 200
        }.resume()

        let deadline = Date().addingTimeInterval(2)
        while available == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return available == true
    }
}
