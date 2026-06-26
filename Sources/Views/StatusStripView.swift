import SwiftUI

struct StatusStripView: View {
    @ObservedObject var session: LectureTranslationSession

    var body: some View {
        HStack(spacing: 8) {
            StatusPill(icon: statusIcon, title: session.statusLine)
            StatusPill(icon: "waveform", title: modelText)
            StatusPill(icon: "timer", title: "\(Int(session.selectedProfile.seconds))s chunks")
            StatusPill(icon: "checkmark.circle", title: "\(session.processedChunks) done")
            StatusPill(icon: "arrow.down.to.line.compact", title: "\(session.droppedChunks) dropped")
            StatusPill(icon: "speaker.slash", title: "\(session.skippedChunks) silent")

            Spacer(minLength: 8)

            if let lastAutosavedAt = session.lastAutosavedAt {
                StatusPill(icon: "tray.and.arrow.down", title: "Autosaved \(lastAutosavedAt.formatted(date: .omitted, time: .shortened))")
            }

            if let lastEventAt = session.lastEventAt {
                StatusPill(icon: "clock", title: lastEventAt.formatted(date: .omitted, time: .standard))
            } else {
                StatusPill(icon: "captions.bubble", title: "No captions yet")
            }
        }
    }

    private var statusIcon: String {
        switch session.state {
        case .idle:
            return "wifi.slash"
        case .opening:
            return "hourglass"
        case .listening:
            return "waveform.circle.fill"
        case .paused:
            return "pause.circle"
        case .stopping:
            return "hourglass"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    private var modelText: String {
        guard let selectedModel = session.selectedModel else {
            return "No model"
        }
        return "\(selectedModel.label) model"
    }
}

private struct StatusPill: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
