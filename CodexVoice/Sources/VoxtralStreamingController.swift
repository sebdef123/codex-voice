import AVFoundation
import Foundation

final class VoxtralStreamingController: NSObject, URLSessionDataDelegate {
    private let sampleRate = 24_000.0
    private var configuredPrebufferSeconds = VoxtralPrebuffer.defaultSeconds
    private var activePrebufferSeconds = VoxtralPrebuffer.defaultSeconds
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var frameBuffer = Data()
    private var activeTaskIdentifier: Int?
    private var startedAt: Date?
    private var onFirstAudio: (() -> Void)?
    private var onFinished: ((VoicePlaybackReport) -> Void)?
    private var onFailure: ((Error) -> Void)?
    private var firstChunkDelay: TimeInterval?
    private var playbackStartDelay: TimeInterval?
    private var streamChunkCount = 0
    private var totalAudioSeconds: TimeInterval = 0
    private var queuedAudioSeconds: TimeInterval = 0
    private var scheduledBuffers = 0
    private var streamEnded = false
    private var didFinish = false
    private var metadata: StreamMetadata?
    private var scheduledPlaybackEnd: Date?
    private var underrunCount = 0
    private var maxUnderrunGap: TimeInterval = 0
    private var responseError: Error?

    var initialPrebufferSeconds: TimeInterval {
        get { configuredPrebufferSeconds }
        set { configuredPrebufferSeconds = VoxtralPrebuffer.clamped(newValue) }
    }

    private struct StreamMetadata: Decodable {
        let audioSeconds: TimeInterval
        let generationSeconds: TimeInterval
        let chunkCount: Int
        let segmentCount: Int?
        let serverCPUSeconds: Double?
        let serverMaxRSSBytes: UInt64?
        let mlxActiveMemoryBytes: UInt64?
        let mlxPeakMemoryBytes: UInt64?
    }

    func speak(text: String, voice: String, onFirstAudio: @escaping () -> Void,
               onFinished: @escaping (VoicePlaybackReport) -> Void, onFailure: @escaping (Error) -> Void) {
        cancelActiveRequest()
        resetState()
        self.onFirstAudio = onFirstAudio
        self.onFinished = onFinished
        self.onFailure = onFailure
        startedAt = Date()
        activePrebufferSeconds = configuredPrebufferSeconds

        guard let url = URL(string: "http://127.0.0.1:8765/speak/stream") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "voice": voice])
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        activeTaskIdentifier = task.taskIdentifier
        task.resume()
    }

    func stop() { cancelActiveRequest() }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard dataTask.taskIdentifier == activeTaskIdentifier else {
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            responseError = VoiceOutputError.invalidResponse("Le flux Voxtral a renvoye une reponse invalide.")
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask.taskIdentifier == activeTaskIdentifier else { return }
        frameBuffer.append(data)
        consumeFrames()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task.taskIdentifier == activeTaskIdentifier else { return }
        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
            fail(VoiceOutputError.unavailable("Connexion Voxtral interrompue: \(error.localizedDescription)."))
            return
        }
        if let responseError {
            fail(responseError)
            return
        }
        guard metadata != nil else {
            fail(VoiceOutputError.invalidResponse("Le flux Voxtral s'est termine sans metadonnees."))
            return
        }
        streamEnded = true
        startPlaybackIfNeeded(force: true)
        finishIfReady()
    }

    private func consumeFrames() {
        while frameBuffer.count >= 5 {
            let header = [UInt8](frameBuffer.prefix(5))
            let payloadLength = (Int(header[1]) << 24) | (Int(header[2]) << 16) | (Int(header[3]) << 8) | Int(header[4])
            guard payloadLength >= 0, frameBuffer.count >= 5 + payloadLength else { return }
            let payload = frameBuffer.subdata(in: 5..<(5 + payloadLength))
            frameBuffer.removeSubrange(0..<(5 + payloadLength))
            switch header[0] {
            case 1: enqueuePCM(payload)
            case 2: metadata = try? JSONDecoder().decode(StreamMetadata.self, from: payload)
            default: fail(VoiceOutputError.invalidResponse("Type de trame Voxtral inconnu."))
            }
        }
    }

    private func enqueuePCM(_ data: Data) {
        guard !data.isEmpty else { return }
        guard let format = audioFormat ?? makeAudioPipeline() else {
            fail(VoiceOutputError.invalidResponse("Impossible d'initialiser la lecture PCM Voxtral."))
            return
        }
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Float>.size)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: Float.self).baseAddress,
                  let destination = buffer.floatChannelData?[0] else { return }
            destination.update(from: source, count: Int(frameCount))
        }

        let duration = TimeInterval(frameCount) / sampleRate
        let now = Date()
        if firstChunkDelay == nil { firstChunkDelay = startedAt.map { now.timeIntervalSince($0) } }
        if playbackStartDelay != nil, let scheduledPlaybackEnd, now.timeIntervalSince(scheduledPlaybackEnd) > 0.025 {
            let gap = now.timeIntervalSince(scheduledPlaybackEnd)
            underrunCount += 1
            maxUnderrunGap = max(maxUnderrunGap, gap)
        }
        scheduledBuffers += 1
        queuedAudioSeconds += duration
        totalAudioSeconds += duration
        streamChunkCount += 1
        playerNode?.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.bufferDidPlay() }
        }

        if playbackStartDelay == nil {
            startPlaybackIfNeeded()
        } else {
            let base = max(scheduledPlaybackEnd ?? now, now)
            scheduledPlaybackEnd = base.addingTimeInterval(duration)
        }
    }

    private func startPlaybackIfNeeded(force: Bool = false) {
        guard playbackStartDelay == nil, queuedAudioSeconds > 0,
              force || queuedAudioSeconds >= activePrebufferSeconds else { return }
        playerNode?.play()
        playbackStartDelay = startedAt.map { Date().timeIntervalSince($0) }
        scheduledPlaybackEnd = Date().addingTimeInterval(queuedAudioSeconds)
        onFirstAudio?()
    }

    private func makeAudioPipeline() -> AVAudioFormat? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else { return nil }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            return nil
        }
        audioEngine = engine
        playerNode = player
        audioFormat = format
        return format
    }

    private func bufferDidPlay() {
        scheduledBuffers = max(0, scheduledBuffers - 1)
        finishIfReady()
    }

    private func finishIfReady() {
        guard streamEnded, scheduledBuffers == 0, playbackStartDelay != nil, !didFinish else { return }
        didFinish = true
        let resources = VoiceResourceReport(
            serverCPUSeconds: metadata?.serverCPUSeconds,
            serverMaxRSSBytes: metadata?.serverMaxRSSBytes,
            mlxActiveMemoryBytes: metadata?.mlxActiveMemoryBytes,
            mlxPeakMemoryBytes: metadata?.mlxPeakMemoryBytes
        )
        onFinished?(VoicePlaybackReport(
            audioDuration: metadata?.audioSeconds ?? totalAudioSeconds,
            generationDuration: metadata?.generationSeconds,
            resources: resources,
            firstChunkDelay: firstChunkDelay,
            playbackStartDelay: playbackStartDelay,
            streamChunkCount: metadata?.chunkCount ?? streamChunkCount,
            streamSegmentCount: metadata?.segmentCount,
            streamUnderrunCount: underrunCount,
            streamMaxGap: maxUnderrunGap == 0 ? nil : maxUnderrunGap
        ))
        cleanupAudio()
    }

    private func fail(_ error: Error) {
        guard !didFinish else { return }
        didFinish = true
        cleanupAudio()
        onFailure?(error)
    }

    private func cancelActiveRequest() {
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
        activeTaskIdentifier = nil
        cleanupAudio()
    }

    private func cleanupAudio() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        audioFormat = nil
    }

    private func resetState() {
        frameBuffer.removeAll(keepingCapacity: true)
        firstChunkDelay = nil
        playbackStartDelay = nil
        streamChunkCount = 0
        totalAudioSeconds = 0
        queuedAudioSeconds = 0
        scheduledBuffers = 0
        streamEnded = false
        didFinish = false
        metadata = nil
        scheduledPlaybackEnd = nil
        underrunCount = 0
        maxUnderrunGap = 0
        responseError = nil
    }
}
