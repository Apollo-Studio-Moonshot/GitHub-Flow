import AppKit

/// Thin wrappers around the AppKit panels used across the app.
@MainActor
enum Pickers {
    static func chooseRepository() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Add Repository"
        panel.message = "Choose a folder that contains a Git repository."
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseDirectory(prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}
