import Foundation

/// Errors surfaced by the git layer. Messages are meant to be shown to users.
enum GitError: LocalizedError, Sendable, Equatable {
    case gitNotFound
    case launchFailed(String)
    case commandFailed(command: String, message: String)
    case notARepository(String)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "Git could not be found on this Mac."
        case .launchFailed(let message):
            return "Unable to run git: \(message)"
        case .commandFailed(_, let message):
            return Self.friendly(message)
        case .notARepository(let path):
            return "“\(path)” is not a git repository."
        case .invalidInput(let message):
            return message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .gitNotFound:
            return "Install the Xcode Command Line Tools (`xcode-select --install`) and try again."
        case .commandFailed(_, let message) where message.contains("could not read Username"):
            return "This repository requires authentication. Configure a git credential helper (for example `git config --global credential.helper osxkeychain`) and try again."
        case .commandFailed:
            return nil
        default:
            return nil
        }
    }

    /// Strips noisy prefixes git adds to stderr.
    private static func friendly(_ message: String) -> String {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["fatal: ", "error: ", "warning: "]
        for prefix in prefixes where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        return text.isEmpty ? "The git command failed." : text
    }
}
