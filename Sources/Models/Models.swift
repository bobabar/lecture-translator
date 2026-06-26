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
    let promptName: String
    let transcriptionPrompt: String

    static let fallbackID = "zh"
    static let all: [SourceLanguage] = [
        .init(
            id: "zh",
            label: "Chinese (Mandarin)",
            promptName: "Mandarin Chinese",
            transcriptionPrompt: "以下是一段中文普通话课堂讲座录音。请用简体中文准确转写普通话内容，保留课程术语、专有名词和数字。"
        ),
        .init(
            id: "en",
            label: "English",
            promptName: "English",
            transcriptionPrompt: "This is an English classroom lecture. Transcribe the speech accurately and preserve terminology, names, and numbers."
        ),
        .init(
            id: "es",
            label: "Spanish",
            promptName: "Spanish",
            transcriptionPrompt: "This is a Spanish classroom lecture. Transcribe the Spanish speech accurately and preserve terminology, names, and numbers."
        ),
        .init(
            id: "fr",
            label: "French",
            promptName: "French",
            transcriptionPrompt: "This is a French classroom lecture. Transcribe the French speech accurately and preserve terminology, names, and numbers."
        ),
        .init(
            id: "de",
            label: "German",
            promptName: "German",
            transcriptionPrompt: "This is a German classroom lecture. Transcribe the German speech accurately and preserve terminology, names, and numbers."
        ),
        .init(
            id: "ja",
            label: "Japanese",
            promptName: "Japanese",
            transcriptionPrompt: "これは日本語の大学講義の録音です。日本語の内容を正確に文字起こしし、専門用語、固有名詞、数字を保ってください。"
        ),
        .init(
            id: "ko",
            label: "Korean",
            promptName: "Korean",
            transcriptionPrompt: "다음은 한국어 강의 녹음입니다. 한국어 내용을 정확히 전사하고 전문 용어, 고유명사, 숫자를 보존하세요."
        ),
        .init(
            id: "ru",
            label: "Russian",
            promptName: "Russian",
            transcriptionPrompt: "This is a Russian classroom lecture. Transcribe the Russian speech accurately and preserve terminology, names, and numbers."
        ),
        .init(
            id: "pt",
            label: "Portuguese",
            promptName: "Portuguese",
            transcriptionPrompt: "This is a Portuguese classroom lecture. Transcribe the Portuguese speech accurately and preserve terminology, names, and numbers."
        ),
        .init(
            id: "it",
            label: "Italian",
            promptName: "Italian",
            transcriptionPrompt: "This is an Italian classroom lecture. Transcribe the Italian speech accurately and preserve terminology, names, and numbers."
        ),
        .init(
            id: "ar",
            label: "Arabic",
            promptName: "Arabic",
            transcriptionPrompt: "هذا تسجيل لمحاضرة باللغة العربية. انسخ الكلام العربي بدقة مع الحفاظ على المصطلحات والأسماء والأرقام."
        ),
        .init(
            id: "hi",
            label: "Hindi",
            promptName: "Hindi",
            transcriptionPrompt: "यह हिंदी कक्षा व्याख्यान की रिकॉर्डिंग है। हिंदी भाषण को सटीक रूप से लिखें और तकनीकी शब्दों, नामों और संख्याओं को सुरक्षित रखें।"
        ),
        .init(
            id: "vi",
            label: "Vietnamese",
            promptName: "Vietnamese",
            transcriptionPrompt: "This is a Vietnamese classroom lecture. Transcribe the Vietnamese speech accurately and preserve terminology, names, and numbers."
        )
    ]

    static func resolve(_ id: String) -> SourceLanguage {
        all.first { $0.id == id } ?? all[0]
    }

    var appleLanguageIdentifier: String {
        switch id {
        case "zh":
            return "zh-Hans"
        default:
            return id
        }
    }
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
