import PortfoxKit
import SwiftUI

/// Ancestry and children of the selected listener, which is what finally makes the
/// Stop target visible.
struct ProcessTreeCard: View {
    @Environment(AppState.self) private var state
    let service: RunningService

    var body: some View {
        DetailCard(title: "Process ancestry & child workers", systemImage: "arrow.triangle.branch") {
            if rows.isEmpty {
                Text("The process tree is not available yet.")
                    .font(.portDetail)
                    .foregroundStyle(Theme.tertiaryText)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows) { line in
                        ProcessLineView(line: line)
                    }
                }
            }
        }
    }

    /// Ancestors outermost first, then the listener, then its children. `children`
    /// rather than `descendants`, because the flat version loses the depth the
    /// indentation is drawn from.
    private var rows: [ProcessLine] {
        guard let tree = state.processTree else { return [] }
        let listener = service.listenerProcess

        var lines: [ProcessLine] = []
        var depth = 0

        for ancestor in tree.ancestors(of: listener.pid).reversed() where ProcessRole.of(ancestor) != .boundary
            || ancestor.pid == service.rootProcess.pid {
            lines.append(line(ancestor, depth: depth))
            depth += 1
        }

        lines.append(line(listener, depth: depth))
        appendChildren(of: listener.pid, depth: depth + 1, tree: tree, into: &lines)
        return lines
    }

    private func line(_ process: ProcessSnapshot, depth: Int) -> ProcessLine {
        ProcessLine(
            process: process,
            depth: depth,
            isStopTarget: process.pid == service.rootProcess.pid,
            isListener: process.pid == service.listenerProcess.pid
        )
    }

    private func appendChildren(of pid: pid_t, depth: Int, tree: ProcessTree, into lines: inout [ProcessLine]) {
        guard depth < 8 else { return }
        for child in tree.children(of: pid).sorted(by: { $0.pid < $1.pid }) {
            lines.append(line(child, depth: depth))
            appendChildren(of: child.pid, depth: depth + 1, tree: tree, into: &lines)
        }
    }
}

struct ProcessLine: Identifiable {
    let process: ProcessSnapshot
    let depth: Int
    let isStopTarget: Bool
    let isListener: Bool

    var id: pid_t { process.pid }

    var role: ProcessRole { ProcessRole.of(process) }

    /// What this row is. `.service` only earns the listener label when it really
    /// holds the socket, so the workers it forks are not all announced as listeners.
    var roleLabel: String {
        if isListener { return "Listening socket" }
        switch role {
        case .boundary: return "Parent shell"
        case .wrapper: return "Runner"
        case .service: return "Worker"
        }
    }

    var hasCommand: Bool { !commandText.isEmpty && commandText.first != "(" }

    /// Nil for a worker fork that reports no executable, where the pid badge
    /// beside it is already the only identity there is.
    var name: String? {
        process.executableName.isEmpty ? nil : process.executableName
    }

    /// Worker forks often expose neither argv nor an executable path, so the row
    /// says so rather than rendering as a bare pid with an empty line beside it.
    var commandText: String {
        if !process.command.isEmpty { return process.command }
        if !process.executableName.isEmpty { return process.executableName }
        return "(no command reported)"
    }

    var roleColor: Color {
        if isListener { return Theme.roleService }
        switch role {
        case .boundary: return Theme.roleBoundary
        case .wrapper: return Theme.roleWrapper
        case .service: return Theme.secondaryText
        }
    }
}

/// One process, indented under its parent so the ancestry reads as containment
/// rather than as a list of indented sentences. Only the listener is boxed; the
/// rest hang off the indent guide, so the nesting does not stack boxes on boxes.
private struct ProcessLineView: View {
    let line: ProcessLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if line.depth > 0 {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1)
                    .padding(.leading, CGFloat(line.depth) * Theme.Metrics.treeIndent)
                    .padding(.trailing, 11)
            }
            card
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow
            commandBox
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if line.isListener {
                CardBackground(fill: Theme.listenerRow, border: Theme.listenerBorder)
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text("PID \(String(line.process.pid))")
                .font(.mono(11, .medium))
                .foregroundStyle(Theme.tertiaryText)

            if let name = line.name {
                Text(name)
                    .font(.mono(12, .semibold))
                    .foregroundStyle(Theme.primaryText)
            }

            TintedBadge(text: line.roleLabel, tint: line.roleColor)
            if line.isStopTarget {
                TintedBadge(text: "Stops here", tint: Theme.danger)
            }

            Spacer(minLength: 8)

            ProcessCPULabel(pid: line.process.pid)
            ProcessMemoryLabel(pid: line.process.pid)
        }
    }

    private var commandBox: some View {
        Text(line.commandText)
            .font(.portSubtitle)
            .foregroundStyle(line.hasCommand ? Theme.secondaryText : Theme.tertiaryText)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.badgeRadius, style: .continuous).fill(Theme.pill)
            )
    }
}
