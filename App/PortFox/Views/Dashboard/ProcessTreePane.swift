import PortFoxKit
import SwiftUI

/// Ancestry and children of the selected listener, which is what finally makes the
/// Stop target visible.
struct ProcessTreePane: View {
    @Environment(AppState.self) private var state
    let service: RunningService
    var scrolls = true

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if scrolls {
            ScrollView { body(for: rows) }
                .scrollBounceBehavior(.basedOnSize)
        } else {
            body(for: rows)
        }
    }

    private func body(for rows: [ProcessLine]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ServiceHeaderCard(service: service, projectIconPath: service.project?.iconPath)

            DetailCard(title: "PROCESS ANCESTRY & CHILD WORKERS", systemImage: "arrow.triangle.branch") {
                if rows.isEmpty {
                    Text("The process tree is not available yet.")
                        .font(.portSubtitle)
                        .foregroundStyle(Theme.tertiaryText)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(rows) { line in
                            ProcessLineView(line: line)
                        }
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
            lines.append(ProcessLine(process: ancestor, depth: depth, isStopTarget: ancestor.pid == service.rootProcess.pid))
            depth += 1
        }

        lines.append(ProcessLine(process: listener, depth: depth, isStopTarget: listener.pid == service.rootProcess.pid))
        appendChildren(of: listener.pid, depth: depth + 1, tree: tree, into: &lines)
        return lines
    }

    private func appendChildren(of pid: pid_t, depth: Int, tree: ProcessTree, into lines: inout [ProcessLine]) {
        guard depth < 8 else { return }
        for child in tree.children(of: pid).sorted(by: { $0.pid < $1.pid }) {
            lines.append(ProcessLine(process: child, depth: depth, isStopTarget: child.pid == service.rootProcess.pid))
            appendChildren(of: child.pid, depth: depth + 1, tree: tree, into: &lines)
        }
    }
}

struct ProcessLine: Identifiable {
    let process: ProcessSnapshot
    let depth: Int
    let isStopTarget: Bool

    var id: pid_t { process.pid }

    var role: ProcessRole { ProcessRole.of(process) }

    var roleLabel: String {
        switch role {
        case .boundary: "Parent Shell"
        case .wrapper: "Runner"
        case .service: "Listener"
        }
    }

    var hasCommand: Bool { !commandText.isEmpty && commandText.first != "(" }

    /// Worker forks often expose neither argv nor an executable path, so the row
    /// says so rather than rendering as a bare pid with an empty line beside it.
    var commandText: String {
        if !process.command.isEmpty { return process.command }
        if !process.executableName.isEmpty { return process.executableName }
        return "(no command reported)"
    }

    var roleColor: Color {
        switch role {
        case .boundary: Theme.roleBoundary
        case .wrapper: Theme.roleWrapper
        case .service: Theme.roleService
        }
    }
}

private struct ProcessLineView: View {
    let line: ProcessLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if line.depth > 0 {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, CGFloat(line.depth) * 14)
            }

            Text("\(line.roleLabel) [PID \(String(line.process.pid))]:")
                .foregroundStyle(line.roleColor)

            Text(line.commandText)
                .foregroundStyle(line.hasCommand ? Theme.secondaryText : Theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            if line.isStopTarget {
                Text("stops here")
                    .font(.portVersion)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.danger.opacity(0.14))
                    )
            }
            Spacer(minLength: 0)
        }
        .font(.portSubtitle)
        .fixedSize(horizontal: false, vertical: true)
    }
}
