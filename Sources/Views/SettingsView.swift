import SwiftUI

struct SettingsView: View {
    @ObservedObject var session: LectureTranslationSession

    var body: some View {
        Form {
            Section("Runtime") {
                LabeledContent("Whisper CLI") {
                    Text(session.runtimeStatus.whisperURL?.path ?? "Not found")
                        .textSelection(.enabled)
                }
                LabeledContent("Resource root") {
                    Text(session.runtimeStatus.resourceRoot?.path ?? "Not found")
                        .textSelection(.enabled)
                }
                LabeledContent("Models") {
                    Text("\(session.models.count)")
                }
            }

            Section("Autosave") {
                LabeledContent("Last autosave") {
                    if let lastAutosavedAt = session.lastAutosavedAt {
                        Text(lastAutosavedAt.formatted(date: .abbreviated, time: .standard))
                    } else {
                        Text("Not yet")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Autosave file") {
                    Text(session.autosaveURL?.path ?? "Created after the first captured text")
                        .textSelection(.enabled)
                }
                Button("Open Autosaves Folder") {
                    session.openAutosaveFolder()
                }
            }

            Section("Defaults") {
                Picker("Model", selection: $session.selectedModelID) {
                    ForEach(session.models) { model in
                        Text("\(model.label) - \(model.sizeLabel)").tag(model.id)
                    }
                }

                Picker("Source language", selection: $session.sourceLanguage) {
                    ForEach(SourceLanguage.all) { language in
                        Text(language.label).tag(language.id)
                    }
                }

                Toggle("Keep source transcript", isOn: $session.includeSourceTranscript)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 620, height: 500)
    }
}
