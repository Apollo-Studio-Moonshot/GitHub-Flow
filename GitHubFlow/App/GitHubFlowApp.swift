import AppKit
import SwiftUI

@main
struct GitHubFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 800)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Existing Repository…") {
                    if let url = Pickers.chooseRepository() {
                        Task { await model.addExistingRepository(at: url) }
                    }
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Clone Repository…") { model.sheet = .clone }
                    .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("New Repository…") { model.sheet = .create }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("Repository") {
                Button("Refresh") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.selectedRepository == nil)

                Button("New Branch…") { model.sheet = .newBranch }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(model.selectedRepository == nil)

                Button("Manage Branches…") { model.sheet = .manageBranches }
                    .disabled(model.selectedRepository == nil)

                Button("Manage Remotes…") { model.sheet = .manageRemotes }
                    .disabled(model.selectedRepository == nil)

                Divider()

                Button("Amend Last Commit…") {
                    Task { await model.beginAmendLastCommit() }
                }
                .disabled(!model.canAmendLastCommit)

                Button("Undo Last Commit…") { model.pendingUndoLastCommit = true }
                    .disabled(!model.canAmendLastCommit)

                Divider()

                Button("Fetch") { Task { await model.fetch() } }
                    .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Pull") { Task { await model.pull() } }
                    .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Push") { Task { await model.push() } }
                    .keyboardShortcut("p", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
