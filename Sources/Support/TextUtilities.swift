import Foundation

func appendUniqueLine(_ current: String, _ nextLine: String) -> String {
    let line = nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return current }

    let currentText = current.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !currentText.isEmpty else { return line }

    let normalizedCurrent = currentText.lowercased()
    let normalizedLine = line.lowercased()

    if normalizedCurrent.hasSuffix(normalizedLine) || normalizedCurrent.contains(normalizedLine) {
        return currentText
    }

    let overlap = suffixPrefixOverlap(currentText, line)
    if overlap > 0 {
        let remainder = String(line.dropFirst(overlap)).trimmingCharacters(in: .newlines)
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? currentText
            : currentText + remainder
    }

    return currentText + "\n" + line
}

private func suffixPrefixOverlap(_ first: String, _ second: String) -> Int {
    let firstCharacters = Array(first)
    let secondCharacters = Array(second)
    let maximum = min(firstCharacters.count, secondCharacters.count)
    guard maximum >= 6 else { return 0 }

    for length in stride(from: maximum, through: 6, by: -1) {
        let suffix = firstCharacters.suffix(length).map { String($0) }.joined().lowercased()
        let prefix = secondCharacters.prefix(length).map { String($0) }.joined().lowercased()
        if suffix == prefix {
            return length
        }
    }

    return 0
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
