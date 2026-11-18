import SwiftUI

struct FlowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.isLoadingFlow && model.flowSummary == nil {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else if let summary = model.flowSummary {
                    hero(summary)
                    actionBar(summary)
                    readiness(summary)
                    if !summary.groups.isEmpty {
                        impact(summary)
                    }
                    pullRequestDraft(summary)
                } else {
                    EmptyStateView(
                        systemName: "point.3.connected.trianglepath.dotted",
                        title: "No flow data yet",
                        message: "Refresh the repository to analyze this branch."
                    )
                    .frame(minHeight: 320)
                }
            }
            .padding(20)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .task(id: flowTaskID) {
            await model.loadFlow()
        }
    }

    private var flowTaskID: String {
        let head = model.commits.first?.sha ?? ""
        let changes = model.snapshot?.changes.count ?? 0
        return "\(model.selectedRepositoryID?.uuidString ?? "none")|\(model.snapshot?.branch ?? "")|\(model.flowBase ?? "auto")|\(head)|\(changes)"
    }

    // MARK: - Hero

    private func hero(_ summary: FlowSummary) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(summary.branch)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if summary.isOnBase {
                        Pill(text: "base branch", tint: Theme.warning)
                    }
                }

                HStack(spacing: 6) {
                    Text("vs")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    basePicker(summary)
                }

                HStack(spacing: 6) {
                    Pill(text: "\(summary.ahead) ahead", systemImage: "arrow.up", tint: Theme.accent)
                    if summary.behind > 0 {
                        Pill(text: "\(summary.behind) behind", systemImage: "arrow.down", tint: Theme.warning)
                    }
                    Pill(text: "\(summary.filesChanged) files", systemImage: "doc.text", tint: .secondary)
                    Text("+\(summary.additions)  −\(summary.deletions)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let age = summary.branchAgeDays {
                    Text("First commit \(age) day\(age == 1 ? "" : "s") ago · last activity \(summary.lastCommitDate?.relativeDescription ?? "—")")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else if summary.isOnBase {
                    Text("Create a short-lived branch before making changes.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 12)

            FlowScoreRing(score: summary.score)
        }
        .padding(18)
        .background(cardBackground)
    }

    private func basePicker(_ summary: FlowSummary) -> some View {
        Menu {
            Button {
                model.setFlowBase(nil)
            } label: {
                Label("Auto-detect", systemImage: summary.baseIsAuto ? "checkmark" : "wand.and.stars")
            }

            if !model.flowBaseOptions.isEmpty {
                Divider()
                ForEach(model.flowBaseOptions, id: \.self) { option in
                    Button {
                        model.setFlowBase(option)
                    } label: {
                        if summary.base == option {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 9, weight: .semibold))
                Text(summary.base ?? "Choose base")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose the branch this work merges into")
    }

    // MARK: - Actions

    private func actionBar(_ summary: FlowSummary) -> some View {
        HStack(spacing: 8) {
            if let url = summary.compareURL, URL(string: url) != nil {
                Button {
                    model.openFlowCompare()
                } label: {
                    Label("Open Pull Request Page", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(ProminentButtonStyle())
                .help("Open the hosting provider’s compare page")
            }

            Button {
                model.copyFlowPRBody()
            } label: {
                Label("Copy PR Draft", systemImage: "doc.on.doc")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(summary.prBody.isEmpty)

            Button {
                Task { await model.explainBranch() }
            } label: {
                Label("Explain", systemImage: "text.bubble")
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            Button {
                Task { await model.fetch() }
            } label: {
                Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.isBusy || !(model.snapshot?.hasRemote ?? false))

            Button {
                Task { await model.loadFlow(force: true) }
            } label: {
                Label("Reanalyze", systemImage: "sparkle.magnifyingglass")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.isBusy || model.isLoadingFlow)
        }
    }

    // MARK: - Readiness

    private func readiness(_ summary: FlowSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Readiness")
                Spacer()
                Text("\(summary.passedCount) of \(summary.checks.filter { $0.level != .info }.count) checks passed")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(summary.checks.enumerated()), id: \.element.id) { index, check in
                    FlowCheckRow(check: check)
                    if index < summary.checks.count - 1 {
                        Divider().opacity(0.45).padding(.leading, 36)
                    }
                }
            }
            .background(cardBackground)
        }
    }

    // MARK: - Impact map

    private func impact(_ summary: FlowSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Impact map")
                Spacer()
                ForEach(summary.riskFlags, id: \.self) { flag in
                    Pill(text: flag, systemImage: "exclamationmark.triangle.fill", tint: Theme.warning)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(summary.groups) { group in
                    ImpactGroupCard(group: group)
                }
            }
        }
    }

    // MARK: - Pull request draft

    private func pullRequestDraft(_ summary: FlowSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Pull request draft")
                Spacer()
                Button {
                    model.copyFlowPRBody()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(summary.prTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .textSelection(.enabled)

                ScrollView {
                    Text(summary.prBody)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
            .fill(Theme.surface.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
    }
}

// MARK: - Pieces

private struct FlowScoreRing: View {
    let score: Int

    private var tint: Color {
        if score >= 75 { return Theme.success }
        if score >= 45 { return Theme.warning }
        return Theme.danger
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 9)

            Circle()
                .trim(from: 0, to: max(0.02, CGFloat(score) / 100))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint, Theme.accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("ready")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .textCase(.uppercase)
            }
        }
        .frame(width: 88, height: 88)
        .help("Branch readiness score")
    }
}

private struct FlowCheckRow: View {
    let check: FlowCheck

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(check.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var symbol: String {
        switch check.level {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.circle.fill"
        case .fail: "xmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch check.level {
        case .pass: Theme.success
        case .warn: Theme.warning
        case .fail: Theme.danger
        case .info: Theme.accentSecondary
        }
    }
}

private struct ImpactGroupCard: View {
    let group: ImpactGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: group.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(group.title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text("\(group.files.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("+\(group.additions) −\(group.deletions)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ForEach(group.files.prefix(6)) { file in
                HStack(spacing: 6) {
                    Text(file.displayName)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !file.directoryPath.isEmpty {
                        Text(file.directoryPath)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    if let flag = file.flags.first {
                        Pill(text: flag, tint: Theme.warning)
                    }
                    if file.isBinary {
                        Pill(text: "binary", tint: .secondary)
                    } else {
                        Text("+\(file.additions) −\(file.deletions)")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .help(file.path)
            }

            if group.files.count > 6 {
                Text("+\(group.files.count - 6) more file\(group.files.count - 6 == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5)
                )
        )
    }
}
