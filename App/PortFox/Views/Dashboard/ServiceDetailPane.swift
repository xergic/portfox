import PortFoxKit
import SwiftUI

struct ServiceDetailPane: View {
    let service: RunningService
    @Bindable var dashboard: DashboardState
    var scrolls = true

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if scrolls {
            ScrollView { panels }.scrollBounceBehavior(.basedOnSize)
        } else {
            panels
        }
    }

    private var panels: some View {
        VStack(alignment: .leading, spacing: 16) {
            ServiceHeaderCard(service: service, projectIconPath: service.project?.iconPath)

            HStack(alignment: .top, spacing: 16) {
                metadata
                if service.localURL != nil {
                    inspection
                }
            }
        }
    }

    private var metadata: some View {
        DetailCard(title: "PROCESS METADATA", systemImage: "terminal") {
            VStack(spacing: 8) {
                LabeledRow(label: "PID", value: String(service.listenerProcess.pid))
                LabeledRow(label: "Executable", value: service.listenerProcess.resolvedExecutablePath)
                LabeledRow(label: "Working directory", value: workingDirectory)
                LabeledRow(label: "Resident memory", value: memory)
                if !service.secondaryPorts.isEmpty {
                    LabeledRow(label: "Other ports", value: service.secondaryPorts.map(String.init).joined(separator: ", "))
                }
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

    private var memory: String? {
        service.listenerProcess.residentMemory.map(ByteFormat.short)
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
