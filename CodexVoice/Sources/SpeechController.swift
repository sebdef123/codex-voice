import AVFoundation
import Foundation

final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {
    struct Voice {
        let identifier: String
        let name: String
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    var voiceIdentifier: String?
    var rate: Float = 0.48

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        stop()
        guard !text.isEmpty else { return }
        AudioDebugLogger.log("speech_start", fields: [
            "engine": "macOS",
            "textLength": text.count,
            "rate": rate
        ])

        let spokenText = PronunciationDictionary.applyForMacOSVoice(to: text)
        if spokenText != text {
            AudioDebugLogger.log("pronunciation_dictionary_applied", fields: [
                "originalLength": text.count,
                "spokenLength": spokenText.count
            ])
        }

        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        }

        activeUtterance = utterance
        synthesizer.speak(utterance)
    }

    func stop() {
        activeUtterance = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func shutdown() {
        stop()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard let activeUtterance, utterance === activeUtterance else { return }
        self.activeUtterance = nil
        AudioDebugLogger.log("speech_engine_finish", fields: ["engine": "macOS"])
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard let activeUtterance, utterance === activeUtterance else { return }
        self.activeUtterance = nil
        AudioDebugLogger.log("speech_engine_cancel", fields: ["engine": "macOS"])
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard let activeUtterance, utterance === activeUtterance else { return }
        onStart?()
    }

    static func availableFrenchVoices() -> [Voice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("fr") }
            .map { Voice(identifier: $0.identifier, name: "\($0.name) (\($0.language))") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
