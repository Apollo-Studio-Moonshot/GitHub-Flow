import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Produces an honest, offline explanation of a change. When the system
/// language model is available (macOS 26+) the UI can ask it to refine the
/// result, but the offline narrative always works and never leaves the Mac.
enum ChangeExplainer {
    static func explain(
        title: String,
        subjects: [String],
        files: [ImpactFile]
    ) -> ChangeExplanation {
        let additions = files.reduce(0) { $0 + $1.additions }
        let deletions = files.reduce(0) { $0 + $1.deletions }
        let groups = FlowAnalyzer.groups(from: files)
        let flags = Array(Set(files.flatMap(\.flags))).sorted()

        var paragraphs: [String] = []

        let areaList = groups.map { "\($0.title.lowercased())" }
        let areaText: String
        switch areaList.count {
        case 0: areaText = "no file areas"
        case 1: areaText = areaList[0]
        case 2: areaText = "\(areaList[0]) and \(areaList[1])"
        default: areaText = areaList.dropLast().joined(separator: ", ") + ", and " + (areaList.last ?? "")
        }

        paragraphs.append(
            "\(title) touches \(files.count) file\(files.count == 1 ? "" : "s") "
                + "(+\(additions) −\(deletions)) across \(areaText)."
        )

        if !subjects.isEmpty {
            let bullets = subjects.prefix(8).map { "• \($0)" }.joined(separator: "\n")
            var commitParagraph = "The work is organized as \(subjects.count) commit\(subjects.count == 1 ? "" : "s"):\n\(bullets)"
            if subjects.count > 8 {
                commitParagraph += "\n• …and \(subjects.count - 8) more."
            }
            paragraphs.append(commitParagraph)
        }

        if !groups.isEmpty {
            let groupLines = groups.map { group -> String in
                let examples = group.files.prefix(3).map(\.displayName).joined(separator: ", ")
                let suffix = group.files.count > 3 ? "…" : ""
                return "• \(group.title): \(group.files.count) file\(group.files.count == 1 ? "" : "s") "
                    + "(\(examples)\(suffix))"
            }
            paragraphs.append("Impact by area:\n" + groupLines.joined(separator: "\n"))
        }

        if flags.isEmpty {
            paragraphs.append("No unusual risk markers were detected.")
        } else {
            paragraphs.append(
                "Worth reviewing closely: "
                    + flags.joined(separator: ", ").lowercased()
                    + ". These files are more likely to need extra eyes before merging."
            )
        }

        if let largest = files.max(by: { $0.changes < $1.changes }), largest.changes > 0 {
            paragraphs.append(
                "Start with \(largest.path) (+\(largest.additions) −\(largest.deletions)); it carries the largest share of the diff."
            )
        }

        return ChangeExplanation(
            title: title,
            text: paragraphs.joined(separator: "\n\n"),
            source: .offline
        )
    }

    static func prompt(
        title: String,
        subjects: [String],
        files: [ImpactFile],
        diff: String?
    ) -> String {
        var lines: [String] = []
        lines.append("Explain this change to a reviewer in at most 180 words. Be concrete and avoid praise.")
        lines.append("Title: \(title)")
        if !subjects.isEmpty {
            lines.append("Commits:\n" + subjects.prefix(10).map { "- \($0)" }.joined(separator: "\n"))
        }
        if !files.isEmpty {
            lines.append(
                "Files:\n"
                    + files.prefix(40).map { "- \($0.path) (+\($0.additions) −\($0.deletions))" }
                    .joined(separator: "\n")
            )
        }
        if let diff, !diff.isEmpty {
            let clipped = String(diff.prefix(8_000))
            lines.append("Diff excerpt:\n\(clipped)")
        }
        return lines.joined(separator: "\n\n")
    }
}

enum OnDeviceExplainer {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    static func explain(prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(
                    instructions: "You are a concise senior software engineer helping a teammate review a code change."
                )
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
