import Foundation

final class WhisperService: @unchecked Sendable {
    private let runtime: WhisperRuntime
    private let timeout: TimeInterval = 120

    init(runtime: WhisperRuntime) {
        self.runtime = runtime
    }

    func transcribe(
        wavData: Data,
        chunkID: Int,
        model: WhisperModel,
        sourceLanguage: String,
        includeSourceTranscript: Bool
    ) throws -> TranscriptionResult {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lecture-translator", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let audioURL = tempDirectory.appendingPathComponent("chunk-\(Date().timeIntervalSince1970)-\(chunkID).wav")
        try wavData.write(to: audioURL, options: [.atomic])
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        let sourceText = includeSourceTranscript
            ? try runWhisper(audioURL: audioURL, model: model, language: sourceLanguage, translate: false)
            : ""

        let translatedText = try runWhisper(
            audioURL: audioURL,
            model: model,
            language: sourceLanguage,
            translate: true
        )

        return TranscriptionResult(
            translatedText: translatedText,
            sourceText: sourceText
        )
    }

    private func runWhisper(
        audioURL: URL,
        model: WhisperModel,
        language: String,
        translate: Bool
    ) throws -> String {
        let status = runtime.status()
        guard let whisperURL = status.whisperURL else {
            throw RuntimeError.whisperUnavailable
        }

        let process = Process()
        process.executableURL = whisperURL
        process.arguments = [
            "-m",
            model.url.path,
            "-f",
            audioURL.path,
            "-l",
            SourceLanguage.all.contains(where: { $0.id == language }) ? language : "auto",
            "-t",
            String(max(2, min(ProcessInfo.processInfo.processorCount, 8))),
            "-nt",
            "-np"
        ]

        if let prompt = prompt(for: language, translate: translate) {
            process.arguments?.append(contentsOf: ["--prompt", prompt])
        }

        if translate {
            process.arguments?.append("-tr")
        }

        var environment = ProcessInfo.processInfo.environment
        if let backendURL = runtime.backendURL(for: whisperURL) {
            environment["GGML_BACKEND_PATH"] = backendURL.path
        }
        if let resourceRoot = status.resourceRoot {
            environment["DYLD_LIBRARY_PATH"] = resourceRoot.appendingPathComponent("lib").path
        }
        process.environment = environment

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.25)
            throw RuntimeError.timeout(model.label)
        }

        let stdout = String(data: standardOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: standardError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw RuntimeError.processFailed(normalizedWhisperOutput(stderr).isEmpty
                ? "whisper-cli exited with code \(process.terminationStatus)."
                : normalizedWhisperOutput(stderr))
        }

        return normalizedWhisperOutput(stdout)
    }

    private func prompt(for language: String, translate: Bool) -> String? {
        switch (language, translate) {
        case ("zh", false):
            return "以下是一段中文课堂讲座录音。请用简体中文准确转写普通话内容，保留课程术语、专有名词和数字。"
        case ("zh", true):
            return "This is a Mandarin Chinese university lecture. Translate the speech into clear, faithful English while preserving technical terms and numbers."
        case ("auto", false):
            return "This is a classroom lecture. Transcribe the spoken source language accurately and preserve terminology, names, and numbers."
        case ("auto", true):
            return "This is a classroom lecture. Translate the speech into clear, faithful English while preserving terminology, names, and numbers."
        default:
            return translate
                ? "Translate this classroom lecture into clear, faithful English while preserving terminology, names, and numbers."
                : "Transcribe this classroom lecture accurately and preserve terminology, names, and numbers."
        }
    }
}
