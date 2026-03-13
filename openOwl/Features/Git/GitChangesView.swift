import Foundation
import SwiftUI

struct GitChangesView: View {
    @EnvironmentObject private var store: GitChangesStore
    @State private var confirmationAction: GitConfirmationAction?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                changesPanel
                    .frame(minWidth: 340, idealWidth: 420)

                diffPanel
                    .frame(minWidth: 420)
            }

            Divider()
            commitPanel
                .frame(minHeight: 150, idealHeight: 170, maxHeight: 220)
        }
        .onAppear {
            store.startIfNeeded()
        }
        .alert("Confirm Action", isPresented: isShowingConfirmation, presenting: confirmationAction) { action in
            switch action {
            case .deleteBranch(let branch):
                Button("Delete", role: .destructive) {
                    store.deleteBranch(name: branch, force: false)
                    confirmationAction = nil
                }
                Button("Force Delete", role: .destructive) {
                    store.deleteBranch(name: branch, force: true)
                    confirmationAction = nil
                }
                Button("Cancel", role: .cancel) {
                    confirmationAction = nil
                }

            case .discardChanges(let changes):
                Button("Discard", role: .destructive) {
                    store.discard(changes)
                    confirmationAction = nil
                }
                Button("Cancel", role: .cancel) {
                    confirmationAction = nil
                }
            }
        } message: { action in
            Text(confirmationMessage(for: action))
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text(store.repositoryURL?.path ?? "No repository selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if !store.branches.isEmpty {
                        Picker("Branch", selection: $store.selectedBranch) {
                            ForEach(store.branches, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)

                        Button("Checkout") {
                            store.checkoutSelectedBranch()
                        }
                        .disabled(store.selectedBranch.isEmpty || store.isRunningCommand)
                    }

                    Button("Fetch") {
                        store.fetch()
                    }
                    .disabled(store.isRunningCommand)

                    Button("Pull") {
                        store.pull()
                    }
                    .disabled(store.isRunningCommand)

                    Button("Push") {
                        store.push()
                    }
                    .disabled(store.isRunningCommand)

                    Button("Choose Repo") {
                        store.chooseRepository()
                    }

                    Button {
                        store.refreshNow()
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .help("Refresh Git status")
                    .disabled(store.isRefreshing || store.isRunningCommand)
                }

                HStack(spacing: 8) {
                    if let trackingText = trackingLabelText {
                        Text(trackingText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    TextField("new-branch-name", text: $store.newBranchName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .font(.system(size: 12, design: .monospaced))

                    Button("Create Branch") {
                        store.createBranchFromInput(checkout: true)
                    }
                    .disabled(store.newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isRunningCommand)

                    Button("Delete Branch") {
                        confirmationAction = .deleteBranch(branch: store.selectedBranch)
                    }
                    .disabled(store.selectedBranch.isEmpty || store.isRunningCommand)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let errorMessage = store.errorMessage {
                statusBanner(text: errorMessage, color: .red) {
                    store.errorMessage = nil
                }
            } else if let infoMessage = store.infoMessage {
                statusBanner(text: infoMessage, color: .green) {
                    store.clearInfoMessage()
                }
            }
        }
    }

    private var trackingLabelText: String? {
        guard let snapshot = store.statusSnapshot else { return nil }

        var parts: [String] = []
        if let upstream = snapshot.upstreamBranch, !upstream.isEmpty {
            parts.append("upstream \(upstream)")
        }
        if snapshot.aheadCount > 0 {
            parts.append("ahead \(snapshot.aheadCount)")
        }
        if snapshot.behindCount > 0 {
            parts.append("behind \(snapshot.behindCount)")
        }
        if parts.isEmpty, let status = snapshot.branchTrackingStatus, !status.isEmpty {
            parts.append(status)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var changesPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Stage All") {
                    store.stageAll()
                }
                .disabled(store.statusSnapshot == nil || store.isRunningCommand)

                Button("Unstage All") {
                    store.unstageAll()
                }
                .disabled(store.statusSnapshot?.staged.isEmpty ?? true || store.isRunningCommand)

                Button("Discard All") {
                    requestDiscard(changes: (store.statusSnapshot?.modified ?? []) + (store.statusSnapshot?.untracked ?? []))
                }
                .disabled(!store.hasDiscardableChanges || store.isRunningCommand)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List {
                changeSection(title: GitChangeSection.staged.rawValue, changes: store.statusSnapshot?.staged ?? [])
                changeSection(title: GitChangeSection.modified.rawValue, changes: store.statusSnapshot?.modified ?? [])
                changeSection(title: GitChangeSection.untracked.rawValue, changes: store.statusSnapshot?.untracked ?? [])
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func changeSection(title: String, changes: [GitFileChange]) -> some View {
        Section("\(title) (\(changes.count))") {
            if changes.isEmpty {
                Text("No files")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(changes) { change in
                    changeRow(change)
                }
            }
        }
    }

    private func changeRow(_ change: GitFileChange) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.path)
                    .lineLimit(1)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))

                Text(change.statusCode)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if change.section == .staged {
                Button("Unstage") {
                    store.unstage(change)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(store.isRunningCommand)
            } else {
                HStack(spacing: 6) {
                    Button("Stage") {
                        store.stage(change)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .disabled(store.isRunningCommand)

                    Button("Discard") {
                        requestDiscard(changes: [change])
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .disabled(store.isRunningCommand)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .background(
            store.selectedChange?.id == change.id ? Color.accentColor.opacity(0.15) : Color.clear
        )
        .onTapGesture {
            store.selectChange(change)
        }
    }

    private var diffPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.selectedChange?.path ?? "Diff")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if store.selectedChange == nil {
                VStack {
                    Spacer()
                    Text("Select a file to view diff")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if store.selectedDiffText.isEmpty {
                VStack {
                    Spacer()
                    Text("No diff output")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffLines.indices, id: \.self) { index in
                            let line = diffLines[index]
                            Text(highlightedLine(line))
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .background(diffBackgroundColor(for: line))
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var commitPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Commit Message")
                    .font(.headline)

                Spacer(minLength: 8)

                Button("Commit") {
                    store.commit()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(store.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isRunningCommand)
            }

            TextEditor(text: $store.commitMessage)
                .font(.system(size: 12, design: .monospaced))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Cmd+Enter to commit. If no staged files exist, commit will auto-stage all changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var diffLines: [String] {
        store.selectedDiffText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private var selectedFileExtension: String? {
        guard let path = store.selectedChange?.path else { return nil }
        guard let ext = path.split(separator: ".").last else { return nil }
        let normalized = ext.lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func highlightedLine(_ line: String) -> AttributedString {
        let outputLine = line.isEmpty ? " " : line
        var attributed = AttributedString(outputLine)
        attributed.foregroundColor = diffForegroundColor(for: line)

        guard let fileExtension = selectedFileExtension else {
            return attributed
        }
        guard !isDiffMetadata(line) else {
            return attributed
        }

        applySyntaxHighlight(to: &attributed, sourceLine: outputLine, fileExtension: fileExtension)
        return attributed
    }

    private func isDiffMetadata(_ line: String) -> Bool {
        line.hasPrefix("diff ")
            || line.hasPrefix("index ")
            || line.hasPrefix("+++")
            || line.hasPrefix("---")
            || line.hasPrefix("@@")
    }

    private func applySyntaxHighlight(
        to attributed: inout AttributedString,
        sourceLine: String,
        fileExtension: String
    ) {
        if let commentPattern = commentPattern(for: fileExtension) {
            applyRegex(
                pattern: commentPattern,
                color: .secondary,
                to: &attributed,
                sourceLine: sourceLine
            )
        }

        applyRegex(
            pattern: #"\"([^\"\\]|\\.)*\"|'([^'\\]|\\.)*'"#,
            color: .orange,
            to: &attributed,
            sourceLine: sourceLine
        )

        guard let keywordPattern = keywordPattern(for: fileExtension) else { return }
        applyRegex(
            pattern: keywordPattern,
            color: .blue,
            to: &attributed,
            sourceLine: sourceLine
        )
    }

    private func applyRegex(
        pattern: String,
        color: Color,
        to attributed: inout AttributedString,
        sourceLine: String
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsRange = NSRange(sourceLine.startIndex..<sourceLine.endIndex, in: sourceLine)

        regex.matches(in: sourceLine, range: nsRange).forEach { match in
            guard let sourceRange = Range(match.range, in: sourceLine),
                  let attributedRange = Range(sourceRange, in: attributed) else { return }
            attributed[attributedRange].foregroundColor = color
        }
    }

    private func keywordPattern(for fileExtension: String) -> String? {
        switch fileExtension {
        case "swift":
            return #"\b(import|let|var|func|struct|class|enum|protocol|extension|if|else|for|while|switch|case|default|guard|return|defer|do|catch|throw|throws|rethrows|try|async|await|actor|where|in)\b"#
        case "ts", "tsx", "js", "jsx":
            return #"\b(import|from|export|const|let|var|function|class|interface|type|extends|implements|if|else|for|while|switch|case|default|return|try|catch|throw|async|await|new|typeof)\b"#
        case "py":
            return #"\b(import|from|as|def|class|if|elif|else|for|while|return|try|except|finally|raise|with|lambda|async|await|yield|pass|break|continue)\b"#
        case "go":
            return #"\b(package|import|func|type|struct|interface|var|const|if|else|for|switch|case|default|return|defer|go|range|map|chan|select)\b"#
        case "rs":
            return #"\b(use|mod|fn|struct|enum|impl|trait|let|mut|if|else|for|while|loop|match|return|pub|crate|self|super|async|await|move)\b"#
        case "java", "kt":
            return #"\b(import|package|class|interface|enum|public|private|protected|static|final|void|var|val|fun|if|else|for|while|switch|case|return|try|catch|throw|new)\b"#
        case "c", "h", "cpp", "hpp", "cc":
            return #"\b(include|define|typedef|struct|enum|class|if|else|for|while|switch|case|return|static|const|void|int|char|float|double|bool|auto|template|namespace)\b"#
        case "sh", "zsh", "bash":
            return #"\b(if|then|else|fi|for|in|do|done|while|case|esac|function|return|export|local)\b"#
        default:
            return nil
        }
    }

    private func commentPattern(for fileExtension: String) -> String? {
        switch fileExtension {
        case "swift", "ts", "tsx", "js", "jsx", "go", "rs", "java", "kt", "c", "h", "cpp", "hpp", "cc":
            return #"//.*$"#
        case "py", "sh", "zsh", "bash", "rb", "yaml", "yml", "toml":
            return #"#.*$"#
        default:
            return nil
        }
    }

    private func statusBanner(text: String, color: Color, onDismiss: @escaping () -> Void) -> some View {
        HStack {
            Text(text)
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
    }

    private func diffForegroundColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return Color(nsColor: .systemGreen)
        }
        if line.hasPrefix("-") && !line.hasPrefix("---") {
            return Color(nsColor: .systemRed)
        }
        if line.hasPrefix("@@") {
            return Color(nsColor: .systemBlue)
        }
        if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("+++") || line.hasPrefix("---") {
            return .secondary
        }
        return .primary
    }

    private func diffBackgroundColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return Color(nsColor: .systemGreen).opacity(0.10)
        }
        if line.hasPrefix("-") && !line.hasPrefix("---") {
            return Color(nsColor: .systemRed).opacity(0.10)
        }
        return Color.clear
    }

    private func requestDiscard(changes: [GitFileChange]) {
        let discardable = changes.filter { $0.section == .modified || $0.section == .untracked }
        guard !discardable.isEmpty else { return }
        confirmationAction = .discardChanges(changes: discardable)
    }

    private var isShowingConfirmation: Binding<Bool> {
        Binding(
            get: { confirmationAction != nil },
            set: { shouldShow in
                if !shouldShow {
                    confirmationAction = nil
                }
            }
        )
    }

    private func confirmationMessage(for action: GitConfirmationAction) -> String {
        switch action {
        case .deleteBranch(let branch):
            return "Delete branch `\(branch)`?"

        case .discardChanges(let changes):
            if changes.count == 1, let change = changes.first {
                return "Discard changes for `\(change.path)`? This action cannot be undone."
            }
            return "Discard \(changes.count) selected changes? This action cannot be undone."
        }
    }
}

private enum GitConfirmationAction {
    case deleteBranch(branch: String)
    case discardChanges(changes: [GitFileChange])
}
