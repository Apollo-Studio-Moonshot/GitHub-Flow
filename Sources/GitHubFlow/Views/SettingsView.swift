import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Commit identity") {
                TextField("Name", text: $model.settings.name)
                    .textFieldStyle(.roundedBorder)
                TextField("Email", text: $model.settings.email)
                    .textFieldStyle(.roundedBorder)

                Text("Used for commits made in this app. Leave the email blank to use your global git configuration.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Appearance") {
                Picker("Theme", selection: $model.settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Git") {
                LabeledContent("Executable") {
                    Text(model.gitPath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LabeledContent("Version") {
                    Text(model.gitVersion ?? "Unknown")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 440)
        .task { await model.loadGitVersion() }
    }
}
