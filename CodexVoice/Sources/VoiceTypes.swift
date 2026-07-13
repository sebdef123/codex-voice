import Foundation

enum VoiceEngineKind: String, CaseIterable {
    case macOS = "macOS TTS"
    case voxtralStreaming = "Voxtral Streaming"

    var userDefaultsValue: String { rawValue }
}

enum VoxtralServerState: Equatable {
    case stopped
    case starting
    case ready
    case unavailable
}

struct VoxtralVoicePreset {
    let identifier: String
    let name: String
}

enum VoxtralVoiceCatalog {
    static let recommended: [VoxtralVoicePreset] = [
        .init(identifier: "fr_female", name: "French female (FR)"),
        .init(identifier: "fr_male", name: "French male (FR)")
    ]

    static let others: [VoxtralVoicePreset] = [
        .init(identifier: "neutral_male", name: "Neutral male (EN)"),
        .init(identifier: "casual_male", name: "Casual male (EN)"),
        .init(identifier: "neutral_female", name: "Neutral female (EN)"),
        .init(identifier: "casual_female", name: "Casual female (EN)"),
        .init(identifier: "cheerful_female", name: "Cheerful female (EN)"),
        .init(identifier: "es_male", name: "Spanish male (ES)"),
        .init(identifier: "es_female", name: "Spanish female (ES)"),
        .init(identifier: "de_male", name: "German male (DE)"),
        .init(identifier: "de_female", name: "German female (DE)"),
        .init(identifier: "it_male", name: "Italian male (IT)"),
        .init(identifier: "it_female", name: "Italian female (IT)"),
        .init(identifier: "pt_male", name: "Portuguese male (PT)"),
        .init(identifier: "pt_female", name: "Portuguese female (PT)"),
        .init(identifier: "nl_male", name: "Dutch male (NL)"),
        .init(identifier: "nl_female", name: "Dutch female (NL)"),
        .init(identifier: "ar_male", name: "Arabic male (AR)"),
        .init(identifier: "hi_male", name: "Hindi male (HI)"),
        .init(identifier: "hi_female", name: "Hindi female (HI)")
    ]

    static var all: [VoxtralVoicePreset] { recommended + others }
}

enum VoxtralPrebuffer {
    static let options: [TimeInterval] = [0.7, 1.0, 1.3, 1.5, 1.8, 2.0, 2.5]
    static let defaultSeconds: TimeInterval = 1.5
    static let minimumSeconds: TimeInterval = 0.7
    static let maximumSeconds: TimeInterval = 2.5

    static func clamped(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, minimumSeconds), maximumSeconds)
    }
}

struct VoiceResourceReport {
    var serverCPUSeconds: Double?
    var serverMaxRSSBytes: UInt64?
    var mlxActiveMemoryBytes: UInt64?
    var mlxPeakMemoryBytes: UInt64?
}

struct VoicePlaybackReport {
    var audioDuration: TimeInterval?
    var generationDuration: TimeInterval?
    var resources: VoiceResourceReport?
    var firstChunkDelay: TimeInterval?
    var playbackStartDelay: TimeInterval?
    var streamChunkCount: Int?
    var streamSegmentCount: Int?
    var streamUnderrunCount: Int?
    var streamMaxGap: TimeInterval?
}

enum VoiceOutputError: LocalizedError {
    case unavailable(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .invalidResponse(let message): return message
        }
    }
}
