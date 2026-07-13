import Foundation

final class VoiceOutputController {
    private final class ActiveRequest {
        let id = UUID()
        let engine: VoiceEngineKind
        let voice: String
        let sourceKind: String
        let rawText: String
        let text: String
        let voxtralPrebufferSeconds: TimeInterval?
        let startedAt = Date()
        let appResources = AppResourceSnapshot.capture()
        var firstAudioAt: Date?

        init(engine: VoiceEngineKind, voice: String, sourceKind: String, rawText: String, text: String,
             voxtralPrebufferSeconds: TimeInterval?) {
            self.engine = engine
            self.voice = voice
            self.sourceKind = sourceKind
            self.rawText = rawText
            self.text = text
            self.voxtralPrebufferSeconds = voxtralPrebufferSeconds
        }
    }

    private let macSpeech = SpeechController()
    private let voxtralSpeech = VoxtralStreamingController()
    private let voxtralServer = VoxtralServerManager()
    private var activeRequest: ActiveRequest?

    var onFinish: (() -> Void)?
    var onFirstAudio: (() -> Void)?
    var onVoxtralStateChange: ((VoxtralServerState) -> Void)?
    var onError: ((String) -> Void)?

    var selectedEngine: VoiceEngineKind = .macOS
    var voiceIdentifier: String? {
        didSet { macSpeech.voiceIdentifier = voiceIdentifier }
    }
    var rate: Float = 0.48 {
        didSet { macSpeech.rate = rate }
    }
    var selectedVoxtralVoice = "fr_female"
    private var storedVoxtralPrebufferSeconds = VoxtralPrebuffer.defaultSeconds
    var voxtralPrebufferSeconds: TimeInterval {
        get { storedVoxtralPrebufferSeconds }
        set {
            storedVoxtralPrebufferSeconds = VoxtralPrebuffer.clamped(newValue)
            voxtralSpeech.initialPrebufferSeconds = storedVoxtralPrebufferSeconds
        }
    }

    var isSpeaking: Bool { activeRequest != nil }

    init() {
        macSpeech.onStart = { [weak self] in self?.didStartMacSpeech() }
        macSpeech.onFinish = { [weak self] in self?.didFinishMacSpeech() }
        voxtralServer.onStateChange = { [weak self] state in
            self?.onVoxtralStateChange?(state)
            AudioDebugLogger.log("voxtral_server_state", fields: ["state": String(describing: state)])
        }
    }

    func selectEngine(_ engine: VoiceEngineKind) {
        guard selectedEngine != engine else {
            if engine == .voxtralStreaming { warmVoxtral() }
            return
        }
        stop(reason: "engine_changed")
        selectedEngine = engine
        AudioDebugLogger.log("engine_selected", fields: ["engine": engine.rawValue])
        switch engine {
        case .macOS:
            voxtralServer.stopIfOwned()
        case .voxtralStreaming:
            warmVoxtral()
        }
    }

    func speak(_ text: String, sourceKind: String, rawText: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if activeRequest != nil { stop(reason: "superseded") }

        let voice = selectedEngine == .macOS ? (voiceIdentifier ?? "French system voice") : selectedVoxtralVoice
        let prebuffer = selectedEngine == .voxtralStreaming ? voxtralPrebufferSeconds : nil
        let request = ActiveRequest(
            engine: selectedEngine,
            voice: voice,
            sourceKind: sourceKind,
            rawText: rawText,
            text: trimmed,
            voxtralPrebufferSeconds: prebuffer
        )
        activeRequest = request
        var logFields: [String: Any] = [:]
        AudioDebugLogger.addTextField(rawText, named: "rawText", to: &logFields)
        AudioDebugLogger.addTextField(trimmed, named: "preparedText", to: &logFields)
        log("tts_requested", request: request, fields: logFields)

        switch request.engine {
        case .macOS:
            startMacSpeech(request)
        case .voxtralStreaming:
            startVoxtralSpeech(request)
        }
    }

    func stop(reason: String = "manual") {
        guard let request = activeRequest else { return }
        let started = Date()
        activeRequest = nil
        macSpeech.stop()
        voxtralSpeech.stop()
        var fields = timingFields(for: request)
        fields["interruptionReason"] = reason
        fields["interruptionToStopSeconds"] = Date().timeIntervalSince(started)
        log("tts_interrupted", request: request, fields: fields)
    }

    func shutdown() {
        stop(reason: "app_terminated")
        voxtralServer.stopIfOwned()
        macSpeech.shutdown()
    }

    func clearDiagnosticLogs() {
        AudioDebugLogger.clearLog()
        voxtralServer.clearLog()
    }

    static func availableFrenchVoices() -> [SpeechController.Voice] {
        SpeechController.availableFrenchVoices()
    }

    private func warmVoxtral() {
        voxtralServer.ensureRunning { [weak self] result in
            if case .failure(let error) = result {
                self?.onError?(error.localizedDescription)
            }
        }
    }

    private func startMacSpeech(_ request: ActiveRequest) {
        guard isActive(request) else { return }
        log("tts_started", request: request)
        macSpeech.voiceIdentifier = voiceIdentifier
        macSpeech.rate = rate
        macSpeech.speak(request.text)
    }

    private func startVoxtralSpeech(_ request: ActiveRequest) {
        voxtralServer.ensureRunning { [weak self] result in
            guard let self, self.isActive(request) else { return }
            switch result {
            case .success:
                self.log("tts_started", request: request)
                // Voxtral receives the prepared text unchanged; macOS-only pronunciation rules stay in SpeechController.
                self.voxtralSpeech.speak(
                    text: request.text,
                    voice: request.voice,
                    onFirstAudio: { [weak self] in self?.didStartVoxtralSpeech(request) },
                    onFinished: { [weak self] report in self?.didFinishVoxtralSpeech(request, report: report) },
                    onFailure: { [weak self] error in self?.fail(request, error: error) }
                )
            case .failure(let error):
                self.fail(request, error: error)
            }
        }
    }

    private func didStartMacSpeech() {
        guard let request = activeRequest, request.engine == .macOS else { return }
        markFirstAudio(request)
    }

    private func didFinishMacSpeech() {
        guard let request = activeRequest, request.engine == .macOS else { return }
        let estimatedAudio = Double(request.text.split(whereSeparator: { $0.isWhitespace }).count) / 2.7
        complete(request, report: VoicePlaybackReport(audioDuration: estimatedAudio, generationDuration: request.firstAudioAt.map { $0.timeIntervalSince(request.startedAt) }))
    }

    private func didStartVoxtralSpeech(_ request: ActiveRequest) {
        guard isActive(request) else { return }
        markFirstAudio(request)
    }

    private func didFinishVoxtralSpeech(_ request: ActiveRequest, report: VoicePlaybackReport) {
        guard isActive(request) else { return }
        complete(request, report: report)
    }

    private func markFirstAudio(_ request: ActiveRequest) {
        guard isActive(request), request.firstAudioAt == nil else { return }
        request.firstAudioAt = Date()
        var fields = timingFields(for: request)
        fields["firstAudioDelaySeconds"] = request.firstAudioAt?.timeIntervalSince(request.startedAt)
        log("tts_first_audio", request: request, fields: fields)
        onFirstAudio?()
    }

    private func complete(_ request: ActiveRequest, report: VoicePlaybackReport) {
        guard isActive(request) else { return }
        activeRequest = nil
        var fields = timingFields(for: request)
        let end = AppResourceSnapshot.capture()
        fields["ttsSeconds"] = Date().timeIntervalSince(request.startedAt)
        fields["audioSeconds"] = report.audioDuration
        fields["generationSeconds"] = report.generationDuration
        fields["generationRTF"] = generationRTF(generation: report.generationDuration ?? request.firstAudioAt.map { $0.timeIntervalSince(request.startedAt) }, audio: report.audioDuration)
        fields["appResidentBytes"] = end.residentBytes
        fields["appCPUSeconds"] = max(0, end.cpuSeconds - request.appResources.cpuSeconds)
        fields["streamFirstChunkDelaySeconds"] = report.firstChunkDelay
        fields["streamPlaybackStartDelaySeconds"] = report.playbackStartDelay
        fields["streamChunkCount"] = report.streamChunkCount
        fields["streamSegmentCount"] = report.streamSegmentCount
        fields["streamUnderrunCount"] = report.streamUnderrunCount
        fields["streamMaxGapSeconds"] = report.streamMaxGap
        fields["serverCPUSeconds"] = report.resources?.serverCPUSeconds
        fields["serverMaxRSSBytes"] = report.resources?.serverMaxRSSBytes
        fields["mlxActiveMemoryBytes"] = report.resources?.mlxActiveMemoryBytes
        fields["mlxPeakMemoryBytes"] = report.resources?.mlxPeakMemoryBytes
        log("tts_finished", request: request, fields: fields)
        onFinish?()
    }

    private func fail(_ request: ActiveRequest, error: Error) {
        guard isActive(request) else { return }
        activeRequest = nil
        var fields = timingFields(for: request)
        fields["error"] = error.localizedDescription
        log("tts_error", request: request, fields: fields)
        onError?(error.localizedDescription)
    }

    private func isActive(_ request: ActiveRequest) -> Bool {
        activeRequest?.id == request.id
    }

    private func timingFields(for request: ActiveRequest) -> [String: Any] {
        var fields: [String: Any] = [
            "engine": request.engine.rawValue,
            "voice": request.voice,
            "sourceKind": request.sourceKind,
            "requestID": request.id.uuidString,
            "textLength": request.text.count
        ]
        if let firstAudioAt = request.firstAudioAt {
            fields["firstAudioDelaySeconds"] = firstAudioAt.timeIntervalSince(request.startedAt)
        }
        if let prebuffer = request.voxtralPrebufferSeconds {
            fields["streamInitialPrebufferSeconds"] = prebuffer
        }
        return fields
    }

    private func log(_ event: String, request: ActiveRequest, fields: [String: Any] = [:]) {
        var payload = timingFields(for: request)
        for (key, value) in fields {
            if let optional = value as? AnyOptional, optional.isNil { continue }
            payload[key] = value
        }
        AudioDebugLogger.log(event, fields: payload)
    }

    private func generationRTF(generation: TimeInterval?, audio: TimeInterval?) -> Double? {
        guard let generation, let audio, audio > 0 else { return nil }
        return generation / audio
    }
}

private protocol AnyOptional { var isNil: Bool { get } }
extension Optional: AnyOptional { var isNil: Bool { self == nil } }
