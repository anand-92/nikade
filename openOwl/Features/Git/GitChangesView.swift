import Foundation
import SwiftUI

struct GitChangesView: View {
    @EnvironmentObject private var store: GitChangesStore
    @State private var confirmationAction: GitConfirmationAction?
    @State private var selectedIDs: Set<String> = []
    @State private var lastClickedID: String?

    var body: some View {
        HSplitView {
            // Left panel: changes + graph
            VSplitView {
                changesPanel
                    .frame(minHeight: 180)

                gitGraphPanel
                    .frame(minHeight: 120)
            }
            .frame(minWidth: 260, idealWidth: 320)

            // Right panel: diff
            diffPanel
                .frame(minWidth: 350)
        }
        .onAppear {
            store.startIfNeeded()
        }
        .alert("Confirm Action", isPresented: isShowingConfirmation, presenting: confirmationAction) { action in
            confirmationButtons(for: action)
        } message: { action in
            Text(confirmationMessage(for: action))
        }
    }

    // MARK: - Left Top: Changes Panel

    private var changesPanel: some View {
        VStack(spacing: 0) {
            commitArea

            Divider()

            // File sections
            ScrollView {
                VStack(spacing: 0) {
                    stagedSection
                    changesSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Error/Info banners
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

    // MARK: - Commit Area (compact, web-style)

    private var commitArea: some View {
        VStack(spacing: 4) {
            // Compact textarea — 1 line default, expands when multiline
            TextEditor(text: $store.commitMessage)
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .frame(height: store.commitMessage.contains("\n") ? 52 : 24)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if store.commitMessage.isEmpty {
                        Text("Commit message")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                store.commit()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                    Text(store.isRunningCommand ? "Committing..." : "Commit")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(
                store.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || store.isRunningCommand
                || !hasAnyChanges
            )
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Staged Changes Section

    @ViewBuilder
    private var stagedSection: some View {
        let staged = store.statusSnapshot?.staged ?? []
        if !staged.isEmpty {
            CollapsibleSection(
                title: "Staged Changes",
                count: staged.count,
                action: {
                    AnyView(
                        Button { store.unstageAll() } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help("Unstage All")
                    )
                }
            ) {
                ForEach(staged) { change in
                    FileStatusRow(
                        change: change,
                        isSelected: selectedIDs.contains(change.id),
                        selectedCount: selectedIDs.count,
                        actionIcon: "minus",
                        actionHelp: "Unstage",
                        onSelect: { handleClick(change) },
                        onAction: {
                            let sel = selectedChanges(in: staged)
                            if sel.count > 1 { store.unstage(paths: sel.map(\.path)) }
                            else { store.unstage(change) }
                        },
                        onDiscard: nil
                    )
                }
            }
        }
    }

    // MARK: - Changes Section (Modified + Untracked)

    @ViewBuilder
    private var changesSection: some View {
        let modified = store.statusSnapshot?.modified ?? []
        let untracked = store.statusSnapshot?.untracked ?? []
        let changes = modified + untracked

        if !changes.isEmpty {
            CollapsibleSection(
                title: "Changes",
                count: changes.count,
                action: {
                    AnyView(
                        HStack(spacing: 2) {
                            Button {
                                requestDiscard(changes: changes)
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .help("Discard All")

                            Button { store.stageAll() } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .help("Stage All")
                        }
                    )
                }
            ) {
                ForEach(changes) { change in
                    FileStatusRow(
                        change: change,
                        isSelected: selectedIDs.contains(change.id),
                        selectedCount: selectedIDs.count,
                        actionIcon: "plus",
                        actionHelp: "Stage",
                        discardable: true,
                        onSelect: { handleClick(change) },
                        onAction: {
                            let sel = selectedChanges(in: changes)
                            if sel.count > 1 { store.stage(paths: sel.map(\.path)) }
                            else { store.stage(change) }
                        },
                        onDiscard: {
                            let sel = selectedChanges(in: changes)
                            if sel.count > 1 { requestDiscard(changes: sel) }
                            else { requestDiscard(changes: [change]) }
                        }
                    )
                }
            }
        }

        if !hasAnyChanges {
            Text("No changes detected")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }

    // MARK: - Left Bottom: Git Graph Panel

    private var gitGraphPanel: some View {
        VStack(spacing: 0) {
            // Toolbar: branch + remote actions
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(store.statusSnapshot?.branch ?? "—")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Ahead/Behind
                if let snapshot = store.statusSnapshot {
                    if snapshot.behindCount > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.down").font(.system(size: 8))
                            Text("\(snapshot.behindCount)").font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                    }
                    if snapshot.aheadCount > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.up").font(.system(size: 8))
                            Text("\(snapshot.aheadCount)").font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Button { store.pull() } label: {
                    Image(systemName: "arrow.down").font(.system(size: 10))
                }
                .buttonStyle(.plain).help("Pull").disabled(store.isRunningCommand)

                Button { store.push() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 10))
                }
                .buttonStyle(.plain).help("Push").disabled(store.isRunningCommand)

                Button { store.refreshNow() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(store.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
                }
                .buttonStyle(.plain).help("Refresh").disabled(store.isRefreshing || store.isRunningCommand)
            }
            .padding(.horizontal, 8)
            .frame(height: AppConstants.terminalToolbarHeight)

            Divider()

            // Commit graph
            if store.logEntries.isEmpty {
                VStack {
                    Spacer()
                    Text("No commits yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    GitGraphContentView(
                        entries: store.logEntries,
                        selectedHash: store.selectedCommitHash,
                        onSelect: { store.selectCommit($0) },
                        onLoadMore: { store.loadMoreLog() },
                        hasMore: store.hasMoreLog
                    )
                }
            }
        }
    }

    // MARK: - Right: Diff Panel

    private var diffPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if let change = store.selectedChange {
                    Text(change.path)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                    Text(change.section == .staged ? "(staged)" : "(working tree)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Diff")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: AppConstants.headerHeight)

            Divider()

            if store.selectedChange == nil {
                Spacer()
                Text("Select a file to view diff")
                    .foregroundStyle(.secondary).font(.system(size: 12))
                Spacer()
            } else if store.selectedDiffText.isEmpty {
                Spacer()
                Text("No diff output")
                    .foregroundStyle(.secondary).font(.system(size: 12))
                Spacer()
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
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Multi-select

    private var allChanges: [GitFileChange] {
        let s = store.statusSnapshot
        return (s?.staged ?? []) + (s?.modified ?? []) + (s?.untracked ?? [])
    }

    private func handleClick(_ change: GitFileChange) {
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.command) {
            // Cmd+Click: toggle
            if selectedIDs.contains(change.id) {
                selectedIDs.remove(change.id)
            } else {
                selectedIDs.insert(change.id)
            }
        } else if modifiers.contains(.shift), let lastID = lastClickedID {
            // Shift+Click: range select
            let items = allChanges
            if let fromIdx = items.firstIndex(where: { $0.id == lastID }),
               let toIdx = items.firstIndex(where: { $0.id == change.id }) {
                let range = min(fromIdx, toIdx)...max(fromIdx, toIdx)
                for i in range { selectedIDs.insert(items[i].id) }
            }
        } else {
            // Normal click: single select
            selectedIDs = [change.id]
        }

        lastClickedID = change.id
        store.selectChange(change)
    }

    private func selectedChanges(in section: [GitFileChange]) -> [GitFileChange] {
        section.filter { selectedIDs.contains($0.id) }
    }

    // MARK: - Helpers

    private var hasAnyChanges: Bool {
        store.statusSnapshot?.hasAnyChanges ?? false
    }

    private var diffLines: [String] {
        store.selectedDiffText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private var selectedFileExtension: String? {
        guard let path = store.selectedChange?.path,
              let ext = path.split(separator: ".").last else { return nil }
        let n = ext.lowercased()
        return n.isEmpty ? nil : n
    }

    private func statusBanner(text: String, color: Color, onDismiss: @escaping () -> Void) -> some View {
        HStack {
            Text(text).font(.system(size: 10)).lineLimit(2)
            Spacer(minLength: 4)
            Button { onDismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 8))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.12))
    }

    private func requestDiscard(changes: [GitFileChange]) {
        let d = changes.filter { $0.section == .modified || $0.section == .untracked }
        guard !d.isEmpty else { return }
        confirmationAction = .discardChanges(changes: d)
    }

    private var isShowingConfirmation: Binding<Bool> {
        Binding(get: { confirmationAction != nil }, set: { if !$0 { confirmationAction = nil } })
    }

    @ViewBuilder
    private func confirmationButtons(for action: GitConfirmationAction) -> some View {
        switch action {
        case .deleteBranch(let branch):
            Button("Delete", role: .destructive) { store.deleteBranch(name: branch, force: false); confirmationAction = nil }
            Button("Force Delete", role: .destructive) { store.deleteBranch(name: branch, force: true); confirmationAction = nil }
            Button("Cancel", role: .cancel) { confirmationAction = nil }
        case .discardChanges(let changes):
            Button("Discard", role: .destructive) { store.discard(changes); confirmationAction = nil }
            Button("Cancel", role: .cancel) { confirmationAction = nil }
        }
    }

    private func confirmationMessage(for action: GitConfirmationAction) -> String {
        switch action {
        case .deleteBranch(let branch): return "Delete branch `\(branch)`?"
        case .discardChanges(let changes):
            if changes.count == 1, let c = changes.first { return "Discard changes for `\(c.path)`? This cannot be undone." }
            return "Discard \(changes.count) changes? This cannot be undone."
        }
    }

    // MARK: - Diff Rendering

    private func highlightedLine(_ line: String) -> AttributedString {
        let outputLine = line.isEmpty ? " " : line
        var attributed = AttributedString(outputLine)
        attributed.foregroundColor = diffForegroundColor(for: line)
        guard let ext = selectedFileExtension, !isDiffMetadata(line) else { return attributed }
        if let cp = commentPattern(for: ext) { applyRegex(pattern: cp, color: .secondary, to: &attributed, sourceLine: outputLine) }
        applyRegex(pattern: #"\"([^\"\\]|\\.)*\"|'([^'\\]|\\.)*'"#, color: .orange, to: &attributed, sourceLine: outputLine)
        if let kp = keywordPattern(for: ext) { applyRegex(pattern: kp, color: .blue, to: &attributed, sourceLine: outputLine) }
        return attributed
    }

    private func isDiffMetadata(_ line: String) -> Bool {
        line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@")
    }

    private func applyRegex(pattern: String, color: Color, to attributed: inout AttributedString, sourceLine: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsRange = NSRange(sourceLine.startIndex..<sourceLine.endIndex, in: sourceLine)
        regex.matches(in: sourceLine, range: nsRange).forEach { match in
            guard let sr = Range(match.range, in: sourceLine), let ar = Range(sr, in: attributed) else { return }
            attributed[ar].foregroundColor = color
        }
    }

    private func keywordPattern(for ext: String) -> String? {
        switch ext {
        case "swift": return #"\b(import|let|var|func|struct|class|enum|protocol|extension|if|else|for|while|switch|case|default|guard|return|defer|do|catch|throw|throws|try|async|await|actor|where|in)\b"#
        case "ts", "tsx", "js", "jsx": return #"\b(import|from|export|const|let|var|function|class|interface|type|if|else|for|while|switch|case|default|return|try|catch|throw|async|await|new|typeof)\b"#
        case "py": return #"\b(import|from|as|def|class|if|elif|else|for|while|return|try|except|finally|raise|with|lambda|async|await|yield)\b"#
        case "go": return #"\b(package|import|func|type|struct|interface|var|const|if|else|for|switch|case|default|return|defer|go|range|map|chan|select)\b"#
        case "rs": return #"\b(use|mod|fn|struct|enum|impl|trait|let|mut|if|else|for|while|loop|match|return|pub|async|await|move)\b"#
        case "c", "h", "cpp", "hpp", "cc": return #"\b(include|define|typedef|struct|enum|class|if|else|for|while|switch|case|return|static|const|void|int|char|float|double|bool|auto)\b"#
        default: return nil
        }
    }

    private func commentPattern(for ext: String) -> String? {
        switch ext {
        case "swift", "ts", "tsx", "js", "jsx", "go", "rs", "java", "kt", "c", "h", "cpp", "hpp", "cc": return #"//.*$"#
        case "py", "sh", "zsh", "bash", "rb", "yaml", "yml", "toml": return #"#.*$"#
        default: return nil
        }
    }

    private func diffForegroundColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color(nsColor: .systemGreen) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color(nsColor: .systemRed) }
        if line.hasPrefix("@@") { return Color(nsColor: .systemBlue) }
        if isDiffMetadata(line) { return .secondary }
        return .primary
    }

    private func diffBackgroundColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color(nsColor: .systemGreen).opacity(0.10) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color(nsColor: .systemRed).opacity(0.10) }
        return Color.clear
    }
}

// MARK: - Git Graph Content (swim lanes + commit list)

private let graphRowHeight: CGFloat = 28
private let graphColWidth: CGFloat = 14
private let graphLeftPad: CGFloat = 8
private let graphCircleR: CGFloat = 4

private let laneColors: [Color] = [
    Color(red: 0.31, green: 0.79, blue: 0.69),  // teal
    Color(red: 0.81, green: 0.57, blue: 0.47),  // salmon
    Color(red: 0.34, green: 0.61, blue: 0.84),  // blue
    Color(red: 0.86, green: 0.86, blue: 0.67),  // yellow
    Color(red: 0.77, green: 0.52, blue: 0.75),  // magenta
    Color(red: 0.61, green: 0.86, blue: 0.99),  // light blue
    Color(red: 0.84, green: 0.73, blue: 0.49),  // gold
    Color(red: 0.71, green: 0.81, blue: 0.66),  // green
    Color(red: 0.82, green: 0.41, blue: 0.41),  // red
    Color(red: 0.38, green: 0.55, blue: 0.31),  // dark green
]

private struct GraphNode {
    let hash: String
    let column: Int
    let row: Int
    let color: Color
}

private struct GraphLayout {
    let nodes: [GraphNode]
    let segments: [(col: Int, row: Int, color: Color)]
    let connectors: [(fromCol: Int, fromRow: Int, toCol: Int, toRow: Int, color: Color)]
    let maxColumns: Int
}

private func computeGraphLayout(entries: [GitLogEntry]) -> GraphLayout {
    guard !entries.isEmpty else {
        return GraphLayout(nodes: [], segments: [], connectors: [], maxColumns: 0)
    }

    var hashToRow: [String: Int] = [:]
    for (i, entry) in entries.enumerated() { hashToRow[entry.hash] = i }

    var lanes: [String?] = []
    var nodes: [GraphNode] = []
    var segments: [(col: Int, row: Int, color: Color)] = []
    var connectors: [(fromCol: Int, fromRow: Int, toCol: Int, toRow: Int, color: Color)] = []
    var maxColumns = 0

    for row in 0..<entries.count {
        let entry = entries[row]
        let hash = entry.hash

        var column = lanes.firstIndex(of: hash) ?? -1
        if column == -1 {
            column = lanes.firstIndex(of: nil as String?) ?? lanes.count
            if column == lanes.count { lanes.append(nil) }
            lanes[column] = hash
        }

        let color = laneColors[column % laneColors.count]
        nodes.append(GraphNode(hash: hash, column: column, row: row, color: color))

        // Collapse duplicate lanes
        for i in (column + 1)..<lanes.count {
            if lanes[i] == hash {
                connectors.append((i, row, column, row, laneColors[i % laneColors.count]))
                lanes[i] = nil
            }
        }

        if entry.parents.isEmpty {
            lanes[column] = nil
        } else {
            let firstParent = entry.parents[0]
            lanes[column] = hashToRow[firstParent] != nil ? firstParent : nil

            for p in 1..<entry.parents.count {
                let parentHash = entry.parents[p]
                guard hashToRow[parentHash] != nil else { continue }
                var parentLane = lanes.firstIndex(of: parentHash) ?? -1
                if parentLane == -1 {
                    parentLane = lanes.firstIndex(of: nil as String?) ?? lanes.count
                    if parentLane == lanes.count { lanes.append(nil) }
                    lanes[parentLane] = parentHash
                }
                if parentLane != column {
                    connectors.append((column, row, parentLane, row + 1, laneColors[parentLane % laneColors.count]))
                }
            }
        }

        while !lanes.isEmpty && lanes.last == nil { lanes.removeLast() }
        maxColumns = max(maxColumns, lanes.count, column + 1)

        if row < entries.count - 1 {
            for c in 0..<lanes.count where lanes[c] != nil {
                segments.append((c, row, laneColors[c % laneColors.count]))
            }
        }
    }

    return GraphLayout(nodes: nodes, segments: segments, connectors: connectors, maxColumns: maxColumns)
}

private struct GitGraphContentView: View {
    let entries: [GitLogEntry]
    let selectedHash: String?
    let onSelect: (String) -> Void
    let onLoadMore: () -> Void
    let hasMore: Bool

    var body: some View {
        let layout = computeGraphLayout(entries: entries)
        let graphWidth = graphLeftPad + CGFloat(max(layout.maxColumns, 1)) * graphColWidth + graphLeftPad

        HStack(alignment: .top, spacing: 0) {
            // SVG-like graph using Canvas
            Canvas { context, _ in
                func cx(_ col: Int) -> CGFloat { graphLeftPad + CGFloat(col) * graphColWidth + graphColWidth / 2 }
                func cy(_ row: Int) -> CGFloat { CGFloat(row) * graphRowHeight + graphRowHeight / 2 }

                // Lane segments
                for seg in layout.segments {
                    var path = Path()
                    path.move(to: CGPoint(x: cx(seg.col), y: cy(seg.row)))
                    path.addLine(to: CGPoint(x: cx(seg.col), y: cy(seg.row + 1)))
                    context.stroke(path, with: .color(seg.color.opacity(0.7)), lineWidth: 1.5)
                }

                // Connectors
                for conn in layout.connectors {
                    let x1 = cx(conn.fromCol), y1 = cy(conn.fromRow)
                    let x2 = cx(conn.toCol), y2 = cy(conn.toRow)
                    var path = Path()
                    path.move(to: CGPoint(x: x1, y: y1))
                    if conn.fromRow == conn.toRow {
                        let belowY = y1 + graphRowHeight / 2
                        path.addQuadCurve(to: CGPoint(x: x2, y: y2), control: CGPoint(x: x1, y: belowY))
                    } else {
                        let midY = (y1 + y2) / 2
                        path.addCurve(to: CGPoint(x: x2, y: y2),
                                       control1: CGPoint(x: x1, y: midY),
                                       control2: CGPoint(x: x2, y: midY))
                    }
                    context.stroke(path, with: .color(conn.color.opacity(0.7)), lineWidth: 1.5)
                }

                // Commit circles
                for node in layout.nodes {
                    let isSelected = node.hash == selectedHash
                    let r = isSelected ? graphCircleR + 1 : graphCircleR
                    let rect = CGRect(x: cx(node.column) - r, y: cy(node.row) - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(node.color))
                    if isSelected {
                        context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
                    }
                }
            }
            .frame(width: graphWidth, height: CGFloat(entries.count) * graphRowHeight)

            // Commit list
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    CommitRow(entry: entry, isSelected: entry.hash == selectedHash)
                        .onTapGesture { onSelect(entry.hash) }
                }

                if hasMore {
                    Text("Loading more...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(height: graphRowHeight)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .onAppear { onLoadMore() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CommitRow: View {
    let entry: GitLogEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            // Ref badges
            if !entry.refs.isEmpty {
                ForEach(parseBadges(), id: \.label) { badge in
                    Text(badge.label)
                        .font(.system(size: 9))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(badge.color.opacity(0.15))
                        .foregroundStyle(badge.color)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }

            // Message
            Text(entry.message)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))

            Spacer(minLength: 4)

            // Relative date
            Text(relativeDate)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: graphRowHeight)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    private struct RefBadge {
        let label: String
        let color: Color
    }

    private func parseBadges() -> [RefBadge] {
        entry.refs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.compactMap { ref in
            if ref.hasPrefix("HEAD -> ") {
                return RefBadge(label: String(ref.dropFirst(8)), color: Color(nsColor: .systemGreen))
            } else if ref.hasPrefix("tag: ") {
                return RefBadge(label: String(ref.dropFirst(5)), color: Color(nsColor: .systemYellow))
            } else if ref.contains("/") {
                return nil  // skip remote refs inline
            } else if ref == "HEAD" {
                return RefBadge(label: "HEAD", color: Color(nsColor: .systemGreen))
            } else {
                return RefBadge(label: ref, color: Color(nsColor: .systemBlue))
            }
        }
    }

    private var relativeDate: String {
        guard let date = ISO8601DateFormatter().date(from: entry.date) else { return "" }
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(diff / 60)m" }
        if diff < 86400 { return "\(diff / 3600)h" }
        if diff < 604800 { return "\(diff / 86400)d" }
        if diff < 2592000 { return "\(diff / 604800)w" }
        if diff < 31536000 { return "\(diff / 2592000)mo" }
        return "\(diff / 31536000)y"
    }
}

// MARK: - Collapsible Section

private struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: Int
    let action: () -> AnyView
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold)).frame(width: 10)
                        Text(title).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                action().opacity(0.7)

                Text("\(count)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)

            if isExpanded { content() }
        }
    }
}

// MARK: - File Status Row

private struct FileStatusRow: View {
    let change: GitFileChange
    let isSelected: Bool
    var selectedCount: Int = 0
    var actionIcon: String
    var actionHelp: String
    var discardable: Bool = false
    let onSelect: () -> Void
    var onAction: (() -> Void)?
    var onDiscard: (() -> Void)?
    @State private var hovering = false

    private var isBatch: Bool { isSelected && selectedCount > 1 }

    private var fileName: String { change.path.split(separator: "/").last.map(String.init) ?? change.path }
    private var dirPath: String {
        guard change.path.contains("/") else { return "" }
        return String(change.path.prefix(upTo: change.path.lastIndex(of: "/")!))
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                Text(fileName).font(.system(size: 11)).foregroundStyle(.primary.opacity(0.85)).lineLimit(1)
                if !dirPath.isEmpty {
                    Text("  \(dirPath)").font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hovering {
                if discardable, let onDiscard {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .onTapGesture { onDiscard() }
                        .help("Discard")
                }
                if let onAction {
                    Image(systemName: actionIcon).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .onTapGesture { onAction() }
                        .help(actionHelp)
                }
            }

            Text(statusLetter)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(statusColor)
                .frame(width: 12, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.15) : (hovering ? Color.secondary.opacity(0.08) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 1) { onSelect() }
        .contextMenu {
            if let onAction {
                let label = change.section == .staged
                    ? (isBatch ? "Unstage \(selectedCount) Files" : "Unstage")
                    : (isBatch ? "Stage \(selectedCount) Files" : "Stage")
                Button(label) { onAction() }
            }
            if discardable, let onDiscard {
                Button(isBatch ? "Discard \(selectedCount) Files" : "Discard Changes") { onDiscard() }
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(change.path, forType: .string)
            }
        }
    }

    private var statusLetter: String {
        switch change.section {
        case .staged: return String(change.indexStatus)
        case .modified: return String(change.workTreeStatus)
        case .untracked: return "U"
        }
    }

    private var statusColor: Color {
        switch statusLetter {
        case "M": return Color(nsColor: .systemYellow)
        case "A": return Color(nsColor: .systemGreen)
        case "D": return Color(nsColor: .systemRed)
        case "R": return Color(nsColor: .systemPurple)
        default: return .secondary
        }
    }
}

private enum GitConfirmationAction {
    case deleteBranch(branch: String)
    case discardChanges(changes: [GitFileChange])
}
