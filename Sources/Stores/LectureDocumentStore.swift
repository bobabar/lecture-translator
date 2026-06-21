import AppKit
import Foundation
import UniformTypeIdentifiers

enum LectureDocumentError: LocalizedError {
    case couldNotCreateAutosaveFolder

    var errorDescription: String? {
        switch self {
        case .couldNotCreateAutosaveFolder:
            return "Could not create the autosave folder."
        }
    }
}

final class LectureDocumentStore: @unchecked Sendable {
    private static let markdownType = UTType(filenameExtension: "md") ?? .plainText

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var autosaveDirectory: URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Lecture Translator", isDirectory: true)
            .appendingPathComponent("Autosaves", isDirectory: true)
    }

    func writeAutosave(_ snapshot: LectureSnapshot) throws -> URL {
        try ensureAutosaveDirectory()
        let url = autosaveDirectory.appendingPathComponent(suggestedFileName(for: snapshot, format: .markdown))
        try render(snapshot, format: .markdown).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    func presentManualSavePanel(for snapshot: LectureSnapshot) -> URL? {
        presentSavePanel(
            title: "Save Lecture Translation",
            prompt: "Save",
            snapshot: snapshot,
            format: .markdown
        )
    }

    @MainActor
    func presentExportPanel(for snapshot: LectureSnapshot) -> (url: URL, format: LectureExportFormat)? {
        let panel = NSSavePanel()
        let formatButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 28), pullsDown: false)
        for format in LectureExportFormat.allCases {
            formatButton.addItem(withTitle: format.label)
        }
        formatButton.selectItem(at: 1)

        panel.title = "Export Lecture Translation"
        panel.prompt = "Export"
        panel.nameFieldStringValue = suggestedFileName(for: snapshot, format: .plainText)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.plainText, Self.markdownType]
        panel.accessoryView = formatButton

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        let selectedFormat = LectureExportFormat.allCases[min(formatButton.indexOfSelectedItem, LectureExportFormat.allCases.count - 1)]
        return (urlWithExtension(url, for: selectedFormat), selectedFormat)
    }

    func write(_ snapshot: LectureSnapshot, to url: URL, format: LectureExportFormat) throws {
        try render(snapshot, format: format).write(to: url, atomically: true, encoding: .utf8)
    }

    func openAutosaveFolder() {
        try? ensureAutosaveDirectory()
        NSWorkspace.shared.activateFileViewerSelecting([autosaveDirectory])
    }

    func suggestedFileName(for snapshot: LectureSnapshot, format: LectureExportFormat) -> String {
        let date = snapshot.startedAt ?? snapshot.updatedAt
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Lecture-Translation-\(formatter.string(from: date)).\(format.fileExtension)"
    }

    private func render(_ snapshot: LectureSnapshot, format: LectureExportFormat) -> String {
        switch format {
        case .markdown:
            return renderMarkdown(snapshot)
        case .plainText:
            return renderPlainText(snapshot)
        }
    }

    private func renderMarkdown(_ snapshot: LectureSnapshot) -> String {
        """
        # Lecture Translation

        - Started: \(formatted(snapshot.startedAt))
        - Updated: \(formatted(snapshot.updatedAt))
        - Source Language: \(snapshot.sourceLanguage)
        - Model: \(snapshot.modelName)
        - Latency Profile: \(snapshot.latencyName)
        - Chunks: \(snapshot.processedChunks) processed, \(snapshot.droppedChunks) dropped, \(snapshot.skippedChunks) silent

        ## English Translation

        \(snapshot.translation.isEmpty ? "_No translated speech yet._" : snapshot.translation)

        ## Source Transcript

        \(snapshot.sourceTranscript.isEmpty ? "_No source transcript yet._" : snapshot.sourceTranscript)
        """
    }

    private func renderPlainText(_ snapshot: LectureSnapshot) -> String {
        """
        Lecture Translation

        Started: \(formatted(snapshot.startedAt))
        Updated: \(formatted(snapshot.updatedAt))
        Source Language: \(snapshot.sourceLanguage)
        Model: \(snapshot.modelName)
        Latency Profile: \(snapshot.latencyName)
        Chunks: \(snapshot.processedChunks) processed, \(snapshot.droppedChunks) dropped, \(snapshot.skippedChunks) silent

        English Translation
        -------------------
        \(snapshot.translation.isEmpty ? "No translated speech yet." : snapshot.translation)

        Source Transcript
        -----------------
        \(snapshot.sourceTranscript.isEmpty ? "No source transcript yet." : snapshot.sourceTranscript)
        """
    }

    @MainActor
    private func presentSavePanel(
        title: String,
        prompt: String,
        snapshot: LectureSnapshot,
        format: LectureExportFormat
    ) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = prompt
        panel.nameFieldStringValue = suggestedFileName(for: snapshot, format: format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [format == .markdown ? Self.markdownType : .plainText]

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return urlWithExtension(url, for: format)
    }

    private func urlWithExtension(_ url: URL, for format: LectureExportFormat) -> URL {
        url.pathExtension == format.fileExtension
            ? url
            : url.deletingPathExtension().appendingPathExtension(format.fileExtension)
    }

    private func ensureAutosaveDirectory() throws {
        do {
            try fileManager.createDirectory(at: autosaveDirectory, withIntermediateDirectories: true)
        } catch {
            throw LectureDocumentError.couldNotCreateAutosaveFolder
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Not started" }
        return date.formatted(date: .abbreviated, time: .standard)
    }
}
