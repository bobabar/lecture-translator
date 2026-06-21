import Foundation

struct AppSettings {
    var selectedModelID: String
    var sourceLanguage: String
    var latencyProfile: String
    var includeSourceTranscript: Bool
}

final class SettingsStore {
    private enum Key {
        static let selectedModelID = "selectedModelID"
        static let sourceLanguage = "sourceLanguage"
        static let latencyProfile = "latencyProfile"
        static let includeSourceTranscript = "includeSourceTranscript"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(defaultModelID: String?) -> AppSettings {
        AppSettings(
            selectedModelID: defaults.string(forKey: Key.selectedModelID) ?? defaultModelID ?? "",
            sourceLanguage: defaults.string(forKey: Key.sourceLanguage) ?? "auto",
            latencyProfile: defaults.string(forKey: Key.latencyProfile) ?? LatencyProfile.balanced.id,
            includeSourceTranscript: defaults.object(forKey: Key.includeSourceTranscript) as? Bool ?? true
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(settings.selectedModelID, forKey: Key.selectedModelID)
        defaults.set(settings.sourceLanguage, forKey: Key.sourceLanguage)
        defaults.set(settings.latencyProfile, forKey: Key.latencyProfile)
        defaults.set(settings.includeSourceTranscript, forKey: Key.includeSourceTranscript)
    }
}
