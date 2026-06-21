import AppKit
import SwiftUI

@main
struct LectureTranslatorNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = TranslationSession()

    var body: some Scene {
        WindowGroup("Lecture Translator", id: "main") {
            ContentView(session: session)
                .frame(minWidth: 980, minHeight: 680)
        }
        .commands {
            CommandMenu("Session") {
                Button("\(session.captureButtonTitle) Listening") {
                    session.toggleCapture()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Save Lecture Translation") {
                    session.saveLecture()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!session.hasReviewContent)

                Button("Export Lecture Translation") {
                    session.exportLecture()
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(!session.hasReviewContent)

                Divider()

                Button("Clear Captions") {
                    session.clearCaptions()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Copy Translation") {
                    session.copyTranslation()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Divider()

                Button("Open Autosaves Folder") {
                    session.openAutosaveFolder()
                }

                Button("Refresh Runtime") {
                    session.refreshRuntime()
                }
            }
        }

        Settings {
            SettingsView(session: session)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
