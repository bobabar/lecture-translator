import Foundation

enum CaptureState: String, Sendable {
    case idle = "Idle"
    case opening = "Opening microphone"
    case listening = "Listening"
    case paused = "Paused"
    case stopping = "Stopping"
    case error = "Unavailable"
}

struct SourceLanguage: Identifiable, Hashable, Sendable {
    let id: String
    let label: String

    static let all: [SourceLanguage] = [
        .init(id: "zh", label: "Chinese (Mandarin)"),
        .init(id: "auto", label: "Auto detect"),
        .init(id: "en", label: "English"),
        .init(id: "es", label: "Spanish"),
        .init(id: "fr", label: "French"),
        .init(id: "de", label: "German"),
        .init(id: "ja", label: "Japanese"),
        .init(id: "ko", label: "Korean"),
        .init(id: "ru", label: "Russian"),
        .init(id: "pt", label: "Portuguese"),
        .init(id: "it", label: "Italian"),
        .init(id: "ar", label: "Arabic"),
        .init(id: "hi", label: "Hindi"),
        .init(id: "vi", label: "Vietnamese")
    ]
}

struct LatencyProfile: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let seconds: Double
    let overlap: Double

    static let all: [LatencyProfile] = [
        .init(id: "fast", label: "Fast", seconds: 6, overlap: 1.5),
        .init(id: "balanced", label: "Lecture", seconds: 12, overlap: 2.5),
        .init(id: "accurate", label: "High Accuracy", seconds: 18, overlap: 4.0)
    ]

    static let balanced = all[1]
}

struct WhisperModel: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let detail: String
    let url: URL
    let sizeBytes: Int64
    let tier: Int

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct RuntimeStatus: Sendable {
    let whisperURL: URL?
    let resourceRoot: URL?
    let defaultModelID: String?
    let models: [WhisperModel]

    var isReady: Bool {
        whisperURL != nil && defaultModelID != nil && !models.isEmpty
    }
}

struct TranscriptionResult: Sendable {
    let translatedText: String
    let sourceText: String
}

struct AudioChunk: Identifiable, Sendable {
    let id: Int
    let wavData: Data
    let modelID: String
}

struct LectureSnapshot: Sendable {
    let id: UUID
    let startedAt: Date?
    let updatedAt: Date
    let sourceLanguage: String
    let modelName: String
    let latencyName: String
    let processedChunks: Int
    let droppedChunks: Int
    let skippedChunks: Int
    let translation: String
    let sourceTranscript: String
}

enum LectureExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case plainText

    var id: String { rawValue }

    var label: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .plainText:
            return "Plain Text"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            return "md"
        case .plainText:
            return "txt"
        }
    }
}
