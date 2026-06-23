import Foundation

struct AppSettings {
    var selectedModelID: String
    var sourceLanguage: String
    var latencyProfile: String
    var includeSourceTranscript: Bool
}

final class SettingsStore {
    private enum Key {
        static let schemaVersion = "settingsSchemaVersion"
        static let selectedModelID = "selectedModelID"
        static let sourceLanguage = "sourceLanguage"
        static let latencyProfile = "latencyProfile"
        static let includeSourceTranscript = "includeSourceTranscript"
    }

    private let currentSchemaVersion = 2
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(defaultModelID: String?) -> AppSettings {
        let schemaVersion = defaults.integer(forKey: Key.schemaVersion)
        let storedSourceLanguage = defaults.string(forKey: Key.sourceLanguage)
        let migratedSourceLanguage = schemaVersion < currentSchemaVersion
            && (storedSourceLanguage == nil || storedSourceLanguage == "auto")
            ? "zh"
            : storedSourceLanguage ?? "zh"

        return AppSettings(
            selectedModelID: defaults.string(forKey: Key.selectedModelID) ?? defaultModelID ?? "",
            sourceLanguage: migratedSourceLanguage,
            latencyProfile: defaults.string(forKey: Key.latencyProfile) ?? LatencyProfile.balanced.id,
            includeSourceTranscript: defaults.object(forKey: Key.includeSourceTranscript) as? Bool ?? true
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(currentSchemaVersion, forKey: Key.schemaVersion)
        defaults.set(settings.selectedModelID, forKey: Key.selectedModelID)
        defaults.set(settings.sourceLanguage, forKey: Key.sourceLanguage)
        defaults.set(settings.latencyProfile, forKey: Key.latencyProfile)
        defaults.set(settings.includeSourceTranscript, forKey: Key.includeSourceTranscript)
    }
}
