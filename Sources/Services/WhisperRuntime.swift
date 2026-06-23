import Foundation

enum RuntimeError: LocalizedError {
    case whisperUnavailable
    case modelUnavailable
    case processFailed(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .whisperUnavailable:
            return "whisper-cli was not found in the app bundle or Homebrew paths."
        case .modelUnavailable:
            return "No Whisper model is available. Add a ggml model to resources/models."
        case .processFailed(let message):
            return message
        case .timeout(let model):
            return "\(model) timed out while processing an audio chunk."
        }
    }
}

final class WhisperRuntime {
    private struct KnownModel {
        let label: String
        let tier: Int
        let detail: String
    }

    private let fileManager = FileManager.default

    private let knownModels: [String: KnownModel] = [
        "ggml-tiny.bin": .init(label: "Tiny", tier: 1, detail: "Fastest, rough captions"),
        "ggml-base.bin": .init(label: "Base", tier: 2, detail: "Fast fallback"),
        "ggml-small.bin": .init(label: "Small", tier: 3, detail: "Fast lecture model for slower Macs"),
        "ggml-medium.bin": .init(label: "Medium", tier: 4, detail: "Higher accuracy, slower"),
        "ggml-large-v3-turbo.bin": .init(label: "Large v3 Turbo", tier: 5, detail: "High accuracy, faster than Large v3"),
        "ggml-large-v3.bin": .init(label: "Large v3", tier: 6, detail: "Best multilingual quality, slowest")
    ]

    func status() -> RuntimeStatus {
        let root = resourceRoot()
        let whisperURL = whisperURL(resourceRoot: root)
        let models = discoverModels(resourceRoot: root)
        let defaultModelID = models.first(where: { $0.id == "ggml-large-v3.bin" })?.id
            ?? models.first(where: { $0.id == "ggml-large-v3-turbo.bin" })?.id
            ?? models.first(where: { $0.id == "ggml-small.bin" })?.id
            ?? models.first(where: { $0.id == "ggml-medium.bin" })?.id
            ?? models.first(where: { $0.id == "ggml-base.bin" })?.id
            ?? models.first?.id

        return RuntimeStatus(
            whisperURL: whisperURL,
            resourceRoot: root,
            defaultModelID: defaultModelID,
            models: models
        )
    }

    func backendURL(for whisperURL: URL) -> URL? {
        let backendDirectory = whisperURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("libexec", isDirectory: true)
        let cpuBrand = cpuBrandString()
        let candidates: [String] = [
            cpuBrand.contains("M4") ? "libggml-cpu-apple_m4.so" : "",
            cpuBrand.contains("M2") || cpuBrand.contains("M3") ? "libggml-cpu-apple_m2_m3.so" : "",
            "libggml-cpu-apple_m1.so",
            "libggml-cpu-apple_m4.so",
            "libggml-cpu-apple_m2_m3.so"
        ].filter { !$0.isEmpty }

        return candidates
            .map { backendDirectory.appendingPathComponent($0) }
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    private func resourceRoot() -> URL? {
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let candidates: [URL?] = [
            ProcessInfo.processInfo.environment["WHISPER_RESOURCE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            Bundle.main.resourceURL,
            currentDirectory.appendingPathComponent("resources", isDirectory: true),
            currentDirectory.appendingPathComponent("lecture-translator-native/resources", isDirectory: true)
        ]

        return candidates.compactMap { $0 }.first { candidate in
            fileManager.fileExists(atPath: candidate.appendingPathComponent("bin/whisper-cli").path)
                || fileManager.fileExists(atPath: candidate.appendingPathComponent("models").path)
        }
    }

    private func whisperURL(resourceRoot: URL?) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let candidates: [URL?] = [
            environment["WHISPER_CLI_PATH"].map { URL(fileURLWithPath: $0) },
            resourceRoot?.appendingPathComponent("bin/whisper-cli"),
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/opt/homebrew/opt/whisper-cpp/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/opt/whisper-cpp/bin/whisper-cli")
        ]

        return candidates.compactMap { $0 }.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func discoverModels(resourceRoot: URL?) -> [WhisperModel] {
        var discovered: [String: WhisperModel] = [:]
        let environment = ProcessInfo.processInfo.environment

        if let modelPath = environment["WHISPER_MODEL_PATH"] {
            let url = URL(fileURLWithPath: modelPath)
            if let model = modelMetadata(for: url) {
                discovered[model.id] = model
            }
        }

        let directories: [URL?] = [
            environment["WHISPER_MODEL_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            resourceRoot?.appendingPathComponent("models", isDirectory: true)
        ]

        for directory in directories.compactMap({ $0 }) {
            let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.lastPathComponent.hasPrefix("ggml-") && url.pathExtension == "bin" {
                if discovered[url.lastPathComponent] == nil, let model = modelMetadata(for: url) {
                    discovered[model.id] = model
                }
            }
        }

        return discovered.values.sorted { lhs, rhs in
            lhs.tier == rhs.tier ? lhs.label < rhs.label : lhs.tier < rhs.tier
        }
    }

    private func modelMetadata(for url: URL) -> WhisperModel? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let attributes = (try? fileManager.attributesOfItem(atPath: url.path)) ?? [:]
        let sizeBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let known = knownModels[url.lastPathComponent]
        let fallbackLabel = url
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "ggml-", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized

        return WhisperModel(
            id: url.lastPathComponent,
            label: known?.label ?? fallbackLabel,
            detail: known?.detail ?? "Custom Whisper model",
            url: url,
            sizeBytes: sizeBytes,
            tier: known?.tier ?? 50
        )
    }

    private func cpuBrandString() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        process.arguments = ["-n", "machdep.cpu.brand_string"]
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
