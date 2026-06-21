import AppKit
import Foundation

@MainActor
final class TranslationSession: ObservableObject {
    @Published private(set) var runtimeStatus = RuntimeStatus(
        whisperURL: nil,
        resourceRoot: nil,
        defaultModelID: nil,
        models: []
    )
    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var statusLine = "Idle"
    @Published private(set) var errorMessage = ""
    @Published private(set) var sourceTranscript = ""
    @Published private(set) var translation = ""
    @Published private(set) var processedChunks = 0
    @Published private(set) var droppedChunks = 0
    @Published private(set) var skippedChunks = 0
    @Published private(set) var startedAt: Date?
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var lastAutosavedAt: Date?
    @Published private(set) var autosaveURL: URL?
    @Published private(set) var lastManualSaveURL: URL?
    @Published private(set) var lastExportURL: URL?

    @Published var selectedModelID = "" {
        didSet { persistSettings() }
    }
    @Published var sourceLanguage = "auto" {
        didSet { persistSettings() }
    }
    @Published var latencyProfileID = LatencyProfile.balanced.id {
        didSet {
            persistSettings()
            audioCapture.update(profile: selectedProfile)
        }
    }
    @Published var includeSourceTranscript = true {
        didSet { persistSettings() }
    }

    private let runtime = WhisperRuntime()
    private lazy var whisperService = WhisperService(runtime: runtime)
    private let audioCapture = AudioCaptureService()
    private let settingsStore = SettingsStore()
    private let documentStore = LectureDocumentStore()

    private var queue: [AudioChunk] = []
    private var isProcessing = false
    private var chunkCounter = 0
    private var isLoadingSettings = true
    private var lectureID = UUID()
    private var autosaveTask: Task<Void, Never>?

    var models: [WhisperModel] {
        runtimeStatus.models
    }

    var selectedModel: WhisperModel? {
        models.first { $0.id == selectedModelID }
            ?? models.first { $0.id == runtimeStatus.defaultModelID }
            ?? models.first
    }

    var selectedProfile: LatencyProfile {
        LatencyProfile.all.first { $0.id == latencyProfileID } ?? .balanced
    }

    var isLive: Bool {
        state == .listening
    }

    var isPaused: Bool {
        state == .paused
    }

    var isBusy: Bool {
        state == .opening || state == .stopping
    }

    var canStart: Bool {
        runtimeStatus.isReady && selectedModel != nil && !isBusy
    }

    var hasReviewContent: Bool {
        !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var captureButtonTitle: String {
        switch state {
        case .listening, .opening, .stopping:
            return "Pause"
        case .paused:
            return "Resume"
        case .idle, .error:
            return "Start"
        }
    }

    var captureButtonIcon: String {
        switch state {
        case .listening, .opening, .stopping:
            return "pause.fill"
        case .paused:
            return "play.fill"
        case .idle, .error:
            return "mic.fill"
        }
    }

    init() {
        refreshRuntime()
    }

    func refreshRuntime() {
        runtimeStatus = runtime.status()
        isLoadingSettings = true
        let settings = settingsStore.load(defaultModelID: runtimeStatus.defaultModelID)
        selectedModelID = models.contains(where: { $0.id == settings.selectedModelID })
            ? settings.selectedModelID
            : runtimeStatus.defaultModelID ?? ""
        sourceLanguage = SourceLanguage.all.contains(where: { $0.id == settings.sourceLanguage })
            ? settings.sourceLanguage
            : "auto"
        latencyProfileID = LatencyProfile.all.contains(where: { $0.id == settings.latencyProfile })
            ? settings.latencyProfile
            : LatencyProfile.balanced.id
        includeSourceTranscript = settings.includeSourceTranscript
        isLoadingSettings = false

        if runtimeStatus.isReady {
            errorMessage = ""
        } else {
            errorMessage = "Whisper is not ready. Confirm the app bundle contains whisper-cli and at least one model."
        }
    }

    func toggleCapture() {
        switch state {
        case .listening, .opening:
            pause()
        case .paused:
            resume()
        case .idle, .error:
            start()
        case .stopping:
            break
        }
    }

    func start() {
        guard canStart else {
            errorMessage = selectedModel == nil ? "Select a Whisper model before starting." : errorMessage
            return
        }

        if !hasReviewContent {
            lectureID = UUID()
            lastAutosavedAt = nil
            autosaveURL = nil
            lastManualSaveURL = nil
            lastExportURL = nil
        }

        state = .opening
        statusLine = "Opening microphone"
        errorMessage = ""
        processedChunks = 0
        droppedChunks = 0
        skippedChunks = 0
        startedAt = nil
        lastEventAt = nil
        queue = []
        chunkCounter = 0

        startCapture()
    }

    func pause() {
        guard state == .listening || state == .opening else { return }
        state = .stopping
        statusLine = isProcessing || !queue.isEmpty ? "Finishing captions" : "Paused"
        audioCapture.stop(flush: true)
        state = .paused
        statusLine = isProcessing || !queue.isEmpty ? "Finishing captions" : "Paused"
        scheduleAutosave()
    }

    func resume() {
        guard state == .paused else { return }
        guard canStart else {
            errorMessage = selectedModel == nil ? "Select a Whisper model before resuming." : errorMessage
            return
        }

        state = .opening
        statusLine = "Opening microphone"
        errorMessage = ""
        startCapture()
    }

    func stop() {
        guard state != .idle else { return }
        state = .stopping
        statusLine = isProcessing || !queue.isEmpty ? "Finishing captions" : "Idle"
        audioCapture.stop(flush: true)
        state = .idle
        scheduleAutosave()
    }

    func clearCaptions() {
        sourceTranscript = ""
        translation = ""
        processedChunks = 0
        droppedChunks = 0
        skippedChunks = 0
        lastEventAt = nil
        lastAutosavedAt = nil
        autosaveURL = nil
        lastManualSaveURL = nil
        lastExportURL = nil
        lectureID = UUID()
        autosaveTask?.cancel()
        queue = []
        chunkCounter = 0
        statusLine = isLive ? "Listening" : isPaused ? "Paused" : "Idle"
    }

    func copyTranslation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translation.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
        statusLine = "Copied"
    }

    func saveLecture() {
        guard hasReviewContent else {
            statusLine = "Nothing to save"
            return
        }

        let snapshot = makeSnapshot()
        guard let url = documentStore.presentManualSavePanel(for: snapshot) else {
            return
        }

        do {
            try documentStore.write(snapshot, to: url, format: .markdown)
            lastManualSaveURL = url
            statusLine = "Saved"
        } catch {
            errorMessage = error.localizedDescription
            statusLine = "Save failed"
        }
    }

    func exportLecture() {
        guard hasReviewContent else {
            statusLine = "Nothing to export"
            return
        }

        let snapshot = makeSnapshot()
        guard let export = documentStore.presentExportPanel(for: snapshot) else {
            return
        }

        do {
            try documentStore.write(snapshot, to: export.url, format: export.format)
            lastExportURL = export.url
            statusLine = "Exported"
        } catch {
            errorMessage = error.localizedDescription
            statusLine = "Export failed"
        }
    }

    func openAutosaveFolder() {
        documentStore.openAutosaveFolder()
    }

    private func startCapture() {
        do {
            try audioCapture.start(profile: selectedProfile) { [weak self] data in
                Task { @MainActor in
                    self?.enqueue(wavData: data)
                }
            } onSkipped: { [weak self] in
                Task { @MainActor in
                    self?.skippedChunks += 1
                }
            }

            state = .listening
            statusLine = "Listening"
            if startedAt == nil {
                startedAt = Date()
            }
            lastEventAt = Date()
            scheduleAutosave()
        } catch {
            audioCapture.stop(flush: false)
            state = .error
            statusLine = "Unavailable"
            errorMessage = error.localizedDescription
        }
    }

    private func enqueue(wavData: Data) {
        guard let model = selectedModel else {
            errorMessage = "Select a Whisper model before starting translation."
            return
        }

        let chunk = AudioChunk(id: chunkCounter, wavData: wavData, modelID: model.id)
        chunkCounter += 1

        if queue.count >= 2 {
            queue.removeFirst()
            droppedChunks += 1
        }

        queue.append(chunk)
        Task { await drainQueue() }
    }

    private func drainQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        while !queue.isEmpty {
            let chunk = queue.removeFirst()
            guard let model = models.first(where: { $0.id == chunk.modelID }) ?? selectedModel else {
                continue
            }

            statusLine = "Translating chunk \(chunk.id + 1)"
            let service = whisperService
            let language = sourceLanguage
            let includeSource = includeSourceTranscript

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try service.transcribe(
                        wavData: chunk.wavData,
                        chunkID: chunk.id,
                        model: model,
                        sourceLanguage: language,
                        includeSourceTranscript: includeSource
                    )
                }.value

                if !result.translatedText.isEmpty {
                    translation = appendUniqueLine(translation, result.translatedText)
                }
                if !result.sourceText.isEmpty {
                    sourceTranscript = appendUniqueLine(sourceTranscript, result.sourceText)
                }

                processedChunks += 1
                lastEventAt = Date()
                scheduleAutosave()
                statusLine = isLive ? "Listening" : isPaused ? "Paused" : "Idle"
            } catch {
                errorMessage = error.localizedDescription
                statusLine = "Whisper error"
            }
        }
    }

    private func scheduleAutosave() {
        guard hasReviewContent || startedAt != nil else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.autosaveNow()
        }
    }

    private func autosaveNow() {
        do {
            let url = try documentStore.writeAutosave(makeSnapshot())
            autosaveURL = url
            lastAutosavedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeSnapshot() -> LectureSnapshot {
        let sourceLanguageName = SourceLanguage.all.first { $0.id == sourceLanguage }?.label ?? sourceLanguage
        return LectureSnapshot(
            id: lectureID,
            startedAt: startedAt,
            updatedAt: Date(),
            sourceLanguage: sourceLanguageName,
            modelName: selectedModel?.label ?? "Unknown",
            latencyName: selectedProfile.label,
            processedChunks: processedChunks,
            droppedChunks: droppedChunks,
            skippedChunks: skippedChunks,
            translation: translation,
            sourceTranscript: sourceTranscript
        )
    }

    private func persistSettings() {
        guard !isLoadingSettings else { return }
        settingsStore.save(
            AppSettings(
                selectedModelID: selectedModelID,
                sourceLanguage: sourceLanguage,
                latencyProfile: latencyProfileID,
                includeSourceTranscript: includeSourceTranscript
            )
        )
    }
}
