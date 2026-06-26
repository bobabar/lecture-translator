import AppKit
import Foundation
@preconcurrency import Translation

typealias AppleTranslationConfiguration = TranslationSession.Configuration
typealias AppleTranslationRuntimeSession = TranslationSession

@MainActor
final class LectureTranslationSession: ObservableObject {
    private struct PendingAppleTranslation: Sendable {
        let id: String
        let sourceText: String
        let generation: Int
    }

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
    @Published private(set) var appleTranslationConfiguration: AppleTranslationConfiguration?

    @Published var selectedModelID = "" {
        didSet { persistSettings() }
    }
    @Published var sourceLanguage = SourceLanguage.fallbackID {
        didSet {
            persistSettings()
            resetAppleTranslationPipeline()
        }
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
    private let maxQueuedChunks = 5

    private var queue: [AudioChunk] = []
    private var isProcessing = false
    private var chunkCounter = 0
    private var isLoadingSettings = true
    private var lectureID = UUID()
    private var autosaveTask: Task<Void, Never>?
    private var pendingTranslationSource = ""
    private var pendingAppleTranslations: [PendingAppleTranslation] = []
    private var isAppleTranslationInFlight = false
    private var appleTranslationCounter = 0
    private var appleTranslationGeneration = 0

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

    var selectedSourceLanguage: SourceLanguage {
        SourceLanguage.resolve(sourceLanguage)
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
            : SourceLanguage.fallbackID
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
        resetAppleTranslationPipeline()

        startCapture()
    }

    func pause() {
        guard state == .listening || state == .opening else { return }
        state = .stopping
        statusLine = isProcessing || !queue.isEmpty ? "Finishing captions" : "Paused"
        audioCapture.stop(flush: true)
        state = .paused
        statusLine = isProcessing || !queue.isEmpty ? "Finishing captions" : "Paused"
        flushPendingTranslationSource()
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
        flushPendingTranslationSource()
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
        resetAppleTranslationPipeline()
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

    nonisolated func processAppleTranslation(with appleSession: AppleTranslationRuntimeSession) async {
        let batch = await takePendingAppleTranslationBatch()
        guard !batch.isEmpty else { return }
        let generation = batch[0].generation

        do {
            await updateStatusLine("Preparing Apple Translate")
            try await appleSession.prepareTranslation()
            await updateStatusLine(batch.count == 1 ? "Translating sentence" : "Translating \(batch.count) sentences")

            let requests = batch.map {
                AppleTranslationRuntimeSession.Request(sourceText: $0.sourceText, clientIdentifier: $0.id)
            }
            let responses = try await appleSession.translations(from: requests)
            await completeAppleTranslationBatch(batch, responses: responses, generation: generation)
        } catch {
            await failAppleTranslation(error, generation: generation)
        }
    }

    private func takePendingAppleTranslationBatch() -> [PendingAppleTranslation] {
        guard isAppleTranslationInFlight else { return [] }

        let batch = pendingAppleTranslations
        pendingAppleTranslations.removeAll()

        if batch.isEmpty {
            isAppleTranslationInFlight = false
        }

        return batch
    }

    private func updateStatusLine(_ message: String) {
        statusLine = message
    }

    private func completeAppleTranslationBatch(
        _ batch: [PendingAppleTranslation],
        responses: [AppleTranslationRuntimeSession.Response],
        generation: Int
    ) {
        guard generation == appleTranslationGeneration else { return }

        let responsesByID: [String: String] = Dictionary(uniqueKeysWithValues: responses.compactMap { response in
            response.clientIdentifier.map { ($0, response.targetText) }
        })

        for item in batch {
            let translatedText = responsesByID[item.id] ?? responses.first(where: { $0.sourceText == item.sourceText })?.targetText
            if let translatedText, !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translation = appendUniqueLine(translation, translatedText)
            }
        }

        lastEventAt = Date()
        scheduleAutosave()
        statusLine = isLive ? "Listening" : isPaused ? "Paused" : "Idle"
        isAppleTranslationInFlight = false
        requestAppleTranslationIfNeeded()
    }

    private func failAppleTranslation(_ error: Error, generation: Int) {
        guard generation == appleTranslationGeneration else { return }

        errorMessage = "Apple Translation failed: \(error.localizedDescription)"
        statusLine = "Translation error"
        isAppleTranslationInFlight = false
        requestAppleTranslationIfNeeded()
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

    private func handleSourceText(_ text: String, flush: Bool) {
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return }

        if includeSourceTranscript {
            sourceTranscript = appendUniqueLine(sourceTranscript, sourceText)
        }

        if selectedSourceLanguage.id == "en" {
            translation = appendUniqueLine(translation, sourceText)
            return
        }

        pendingTranslationSource = appendUniqueLine(pendingTranslationSource, sourceText)
        let extracted = extractTranslationUnits(
            from: pendingTranslationSource,
            flush: flush,
            maximumCharacters: maximumTranslationUnitCharacters
        )
        pendingTranslationSource = extracted.remainder
        for unit in extracted.units {
            enqueueAppleTranslation(unit)
        }
        requestAppleTranslationIfNeeded()
    }

    private func flushPendingTranslationSource() {
        let extracted = extractTranslationUnits(
            from: pendingTranslationSource,
            flush: true,
            maximumCharacters: maximumTranslationUnitCharacters
        )
        pendingTranslationSource = extracted.remainder
        for unit in extracted.units {
            enqueueAppleTranslation(unit)
        }
        requestAppleTranslationIfNeeded()
    }

    private func enqueueAppleTranslation(_ text: String) {
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return }

        pendingAppleTranslations.append(
            PendingAppleTranslation(
                id: "translation-\(appleTranslationCounter)",
                sourceText: sourceText,
                generation: appleTranslationGeneration
            )
        )
        appleTranslationCounter += 1
    }

    private func requestAppleTranslationIfNeeded() {
        guard !pendingAppleTranslations.isEmpty, !isAppleTranslationInFlight else { return }

        let source = Locale.Language(identifier: selectedSourceLanguage.appleLanguageIdentifier)
        let target = Locale.Language(identifier: "en")
        isAppleTranslationInFlight = true

        if var configuration = appleTranslationConfiguration,
           configuration.source == source,
           configuration.target == target {
            configuration.invalidate()
            appleTranslationConfiguration = configuration
        } else {
            appleTranslationConfiguration = AppleTranslationConfiguration(source: source, target: target)
        }
    }

    private func resetAppleTranslationPipeline() {
        pendingTranslationSource = ""
        pendingAppleTranslations = []
        isAppleTranslationInFlight = false
        appleTranslationCounter = 0
        appleTranslationGeneration += 1
        appleTranslationConfiguration = nil
    }

    private var maximumTranslationUnitCharacters: Int {
        switch selectedSourceLanguage.id {
        case "zh", "ja", "ko":
            return 120
        default:
            return 240
        }
    }

    private func enqueue(wavData: Data) {
        guard let model = selectedModel else {
            errorMessage = "Select a Whisper model before starting translation."
            return
        }

        let chunk = AudioChunk(id: chunkCounter, wavData: wavData, modelID: model.id)
        chunkCounter += 1

        if queue.count >= maxQueuedChunks {
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

            statusLine = "Transcribing chunk \(chunk.id + 1)"
            let service = whisperService
            let language = sourceLanguage

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try service.transcribe(
                        wavData: chunk.wavData,
                        chunkID: chunk.id,
                        model: model,
                        sourceLanguage: language
                    )
                }.value

                if !result.sourceText.isEmpty {
                    handleSourceText(result.sourceText, flush: !isLive)
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
