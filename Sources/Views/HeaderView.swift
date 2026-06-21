import SwiftUI

struct HeaderView: View {
    @ObservedObject var session: TranslationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "translate")
                    .font(.system(size: 25, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
                    .background(.teal.gradient, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Lecture Translator")
                        .font(.title2.weight(.bold))
                    Text("Local Whisper, multilingual speech, English captions")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                CaptureButton(session: session)
            }

            ControlsView(session: session)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CaptureButton: View {
    @ObservedObject var session: TranslationSession

    var body: some View {
        Button {
            session.toggleCapture()
        } label: {
            Label(session.captureButtonTitle, systemImage: session.captureButtonIcon)
                .frame(minWidth: 86)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(session.isLive || session.isBusy ? .orange : .teal)
        .disabled(!session.canStart && !session.isLive && !session.isBusy)
    }
}

private struct ControlsView: View {
    @ObservedObject var session: TranslationSession

    var body: some View {
        HStack(spacing: 8) {
            Picker("Model", selection: $session.selectedModelID) {
                ForEach(session.models) { model in
                    Text("\(model.label) - \(model.sizeLabel)").tag(model.id)
                }
            }
            .frame(minWidth: 220)
            .disabled(session.isLive || session.isBusy || session.models.isEmpty)

            Picker("Source", selection: $session.sourceLanguage) {
                ForEach(SourceLanguage.all) { language in
                    Text(language.label).tag(language.id)
                }
            }
            .frame(minWidth: 150)
            .disabled(session.isLive || session.isBusy)

            Picker("Latency", selection: $session.latencyProfileID) {
                ForEach(LatencyProfile.all) { profile in
                    Text(profile.label).tag(profile.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)
            .disabled(session.isLive || session.isBusy)

            Toggle(isOn: $session.includeSourceTranscript) {
                Label("Source", systemImage: "text.quote")
            }
            .toggleStyle(.button)
            .disabled(session.isLive || session.isBusy)

            Button {
                session.clearCaptions()
            } label: {
                Label("Clear", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .help("Clear captions")
            .disabled(session.translation.isEmpty && session.sourceTranscript.isEmpty)

            Button {
                session.copyTranslation()
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
                    .labelStyle(.iconOnly)
            }
            .help("Copy English translation")
            .disabled(session.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                session.saveLecture()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .labelStyle(.iconOnly)
            }
            .help("Save lecture translation")
            .disabled(!session.hasReviewContent)

            Button {
                session.exportLecture()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
            .help("Export lecture translation")
            .disabled(!session.hasReviewContent)
        }
    }
}
