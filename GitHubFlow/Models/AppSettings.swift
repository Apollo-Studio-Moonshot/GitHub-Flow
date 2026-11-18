import Foundation

enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// User preferences. When a name and email are set they override the
/// repository's git configuration for commits made by this app.
struct AppSettings: Codable, Sendable, Equatable {
    var name: String = ""
    var email: String = ""
    var appearance: AppearanceMode = .system

    var identity: GitIdentity? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return nil }
        return GitIdentity(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: trimmedEmail)
    }
}

struct GitIdentity: Sendable, Equatable {
    var name: String
    var email: String
}

enum Persistence {
    private static let repositoriesKey = "GitHubFlow.repositories.v1"
    private static let settingsKey = "GitHubFlow.settings.v1"

    static func loadRepositories() -> [RepositoryRef] {
        guard let data = UserDefaults.standard.data(forKey: repositoriesKey),
              let repositories = try? JSONDecoder().decode([RepositoryRef].self, from: data) else {
            return []
        }
        return repositories
    }

    static func saveRepositories(_ repositories: [RepositoryRef]) {
        guard let data = try? JSONEncoder().encode(repositories) else { return }
        UserDefaults.standard.set(data, forKey: repositoriesKey)
    }

    static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    static func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }
}
