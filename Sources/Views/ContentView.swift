import SwiftUI
@preconcurrency import Translation

struct ContentView: View {
    @ObservedObject var session: LectureTranslationSession

    var body: some View {
        content
            .translationTask(session.appleTranslationConfiguration) { appleSession in
                await session.processAppleTranslation(with: appleSession)
            }
    }

    private var content: some View {
        VStack(spacing: 14) {
            HeaderView(session: session)
            StatusStripView(session: session)

            if !session.errorMessage.isEmpty {
                ErrorBanner(message: session.errorMessage) {
                    session.refreshRuntime()
                }
            }

            HStack(alignment: .top, spacing: 14) {
                TranscriptPane(
                    title: "English Translation",
                    text: session.translation,
                    placeholder: "Awaiting translated speech",
                    isPrimary: true
                )

                TranscriptPane(
                    title: "Source Transcript",
                    text: session.sourceTranscript,
                    placeholder: "Awaiting source speech",
                    isPrimary: false
                )
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 460)
            }
        }
        .padding(16)
        .background(.background)
        .onReceive(NotificationCenter.default.publisher(for: .toggleCapture)) { _ in
            session.toggleCapture()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearCaptions)) { _ in
            session.clearCaptions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyTranslation)) { _ in
            session.copyTranslation()
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button("Refresh", action: refresh)
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
