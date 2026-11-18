import SwiftUI

struct ExplanationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)

            if let explanation = model.explanation {
                ScrollView {
                    Text(explanation.text)
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }
                .background(Theme.canvas)

                Divider().opacity(0.6)
                footer(explanation)
            } else {
                EmptyStateView(
                    systemName: "text.bubble",
                    title: "Nothing to explain",
                    message: "Select a commit or run the branch explanation from the Flow tab."
                )
            }
        }
        .frame(width: 640, height: 520)
        .background(Theme.canvas)
    }

    private var header: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.accent.opacity(0.14))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "text.bubble")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(model.explanation?.title ?? "Explain Change")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let explanation = model.explanation {
                        Pill(text: explanation.source.title, tint: explanation.source == .onDevice ? Theme.success : Theme.accentSecondary)
                    }
                    Text("Generated locally; your code never leaves this Mac.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                if let text = model.explanation?.text {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    model.showToast("Copied explanation")
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.surface.opacity(0.4))
    }

    private func footer(_ explanation: ChangeExplanation) -> some View {
        HStack(spacing: 8) {
            if OnDeviceExplainer.isAvailable {
                Button {
                    Task { await model.refineExplanationWithOnDevice() }
                } label: {
                    if model.isExplaining {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Thinking…")
                        }
                    } else {
                        Label(
                            explanation.source == .onDevice ? "Regenerate with On-Device Model" : "Refine with On-Device Model",
                            systemImage: "sparkles"
                        )
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isExplaining)
            } else {
                Text("On-device model unavailable on this macOS version.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(ProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.surface.opacity(0.35))
    }
}
