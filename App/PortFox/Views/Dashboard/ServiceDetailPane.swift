import PortFoxKit
import SwiftUI

struct ServiceDetailPane: View {
    let service: RunningService
    @Bindable var dashboard: DashboardState
    var scrolls = true

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The padding lives inside the scroll view, not around it, so the overlay
    /// scroller rides the window edge instead of sitting on top of the content.
    @ViewBuilder
    private var content: some View {
        if scrolls {
            ScrollView { panels.padding(16) }.scrollBounceBehavior(.basedOnSize)
        } else {
            panels.padding(16)
        }
    }

    private var panels: some View {
        VStack(alignment: .leading, spacing: 16) {
            ServiceHeaderView(service: service, projectIconPath: service.project?.iconPath)
            CardDivider()

            HStack(alignment: .top, spacing: 16) {
                metadata
                if service.localURL != nil {
                    inspection
                }
            }

            ProcessTreeCard(service: service)
        }
    }

    private var metadata: some View {
        DetailCard(title: "PROCESS METADATA", systemImage: "terminal") {
            VStack(spacing: 8) {
                LabeledRow(label: "PID", value: String(service.listenerProcess.pid), layout: .inline)
                LabeledRow(
                    label: "Executable",
                    value: service.listenerProcess.resolvedExecutablePath,
                    layout: .inline,
                    valueColor: Theme.pathExecutable
                )
                LabeledRow(
                    label: "Working directory",
                    value: workingDirectory,
                    layout: .inline,
                    valueColor: Theme.pathDirectory
                )
                if !service.secondaryPorts.isEmpty {
                    LabeledRow(
                        label: "Other ports",
                        value: service.secondaryPorts.map(String.init).joined(separator: ", "),
                        layout: .inline
                    )
                }
                CardDivider()
                ResidentMemoryRow(pid: service.listenerProcess.pid)
            }
        }
    }

    private var inspection: some View {
        DetailCard(title: "HTTP INSPECTION", systemImage: "globe") {
            VStack(spacing: 8) {
                switch dashboard.probeResult(for: service) {
                case .success(let probe):
                    LabeledRow(
                        label: "Status",
                        value: nil,
                        badge: StatusPill(text: statusText(probe.statusCode), tint: statusTint(probe.statusCode))
                    )
                    LabeledRow(label: "Page title", value: probe.title)
                    if let location = probe.location {
                        LabeledRow(label: "Redirects to", value: location)
                    }
                    LabeledRow(label: "Server header", value: probe.server)
                    LabeledRow(label: "Response latency", value: latency(probe.latency))
                case .failure(let message):
                    Text(message)
                        .font(.portSubtitle)
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case nil:
                    Text("Not inspected yet. PortFox never probes a server on its own.")
                        .font(.portSubtitle)
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                probeButton
            }
        }
    }

    private var probeButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                Task { await dashboard.runProbe(for: service) }
            } label: {
                Text(dashboard.isProbing(service) ? "Inspecting…" : inspectLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.cardHover)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Theme.border, lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(dashboard.isProbing(service))
        }
        .padding(.top, 2)
    }

    private var inspectLabel: String {
        dashboard.probeResult(for: service) == nil ? "Inspect" : "Inspect again"
    }

    private var workingDirectory: String? {
        guard let path = service.listenerProcess.workingDirectory else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func latency(_ duration: Duration) -> String {
        let milliseconds = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
        return "\(Int(milliseconds.rounded())) ms"
    }

    private func statusText(_ code: Int) -> String {
        "\(String(code)) \(HTTPURLResponse.localizedString(forStatusCode: code).uppercased())"
    }

    private func statusTint(_ code: Int) -> Color {
        switch code {
        case 200..<300: Theme.accent
        case 300..<400: Theme.roleWrapper
        default: Theme.danger
        }
    }
}
