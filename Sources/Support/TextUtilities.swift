import Foundation

func appendUniqueLine(_ current: String, _ nextLine: String) -> String {
    let line = nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return current }

    let normalizedCurrent = current.lowercased()
    let normalizedLine = line.lowercased()

    if normalizedCurrent.hasSuffix(normalizedLine) || normalizedCurrent.contains("\n\(normalizedLine)\n") {
        return current
    }

    let separator = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n"
    return current.trimmingCharacters(in: .whitespacesAndNewlines) + separator + line
}

func normalizedWhisperOutput(_ text: String) -> String {
    text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { line in
            !line.isEmpty
                && !line.hasPrefix("whisper_")
                && !line.hasPrefix("ggml_")
                && !line.hasPrefix("load_backend:")
                && !line.hasPrefix("read_audio_data:")
                && !line.hasPrefix("system_info:")
        }
        .joined(separator: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
