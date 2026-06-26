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
        sourceLanguage: String
    ) throws -> TranscriptionResult {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lecture-translator", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let audioURL = tempDirectory.appendingPathComponent("chunk-\(Date().timeIntervalSince1970)-\(chunkID).wav")
        try wavData.write(to: audioURL, options: [.atomic])
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        let language = SourceLanguage.resolve(sourceLanguage)
        let sourceText = try runWhisper(audioURL: audioURL, model: model, language: language)

        return TranscriptionResult(
            sourceText: sourceText
        )
    }

    private func runWhisper(
        audioURL: URL,
        model: WhisperModel,
        language: SourceLanguage
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
            language.id,
            "-t",
            String(max(2, min(ProcessInfo.processInfo.processorCount, 8))),
            "-nt",
            "-np",
            "-sns",
            "--prompt",
            language.transcriptionPrompt,
            "--carry-initial-prompt"
        ]

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
}
