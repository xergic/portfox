import PortfoxKit
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

            // A container's real process lives in a VM. The tree here would be
            // the forwarder's, identical on every row of the stack.
            if service.hasHostProcess {
                ProcessTreeCard(service: service)
            }
        }
    }

    private var metadata: some View {
        DetailCard(title: "Process metadata", systemImage: "terminal") {
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
                // Both read the forwarder, which is shared, so on a container row
                // they would report the whole daemon against one container.
                if service.hasHostProcess {
                    CardDivider()
                    ResidentMemoryRow(pid: service.listenerProcess.pid)
                    CPUUsageRow(pid: service.listenerProcess.pid)
                }
            }
        }
    }

    private var inspection: some View {
        DetailCard(title: "HTTP inspection", systemImage: "globe") {
            VStack(spacing: 8) {
                switch dashboard.probeResult(for: service) {
                case .success(let probe):
                    LabeledRow(
                        label: "Status",
                        value: nil,
                        badge: TintedBadge(text: statusText(probe.statusCode), tint: statusTint(probe.statusCode))
                    )
                    LabeledRow(label: "Page title", value: probe.title, valueFont: .portDetail)
                    if let location = probe.location {
                        LabeledRow(label: "Redirects to", value: location)
                    }
                    LabeledRow(label: "Server header", value: probe.server)
                    LabeledRow(label: "Response latency", value: latency(probe.latency))
                case .failure(let message):
                    Text(message)
                        .font(.portDetail)
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case nil:
                    Text("Not inspected yet. Portfox never probes a server on its own.")
                        .font(.portDetail)
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
            ActionButton(symbol: "waveform.path.ecg", label: dashboard.isProbing(service) ? "Inspecting…" : inspectLabel) {
                Task { await dashboard.runProbe(for: service) }
            }
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
        let reason = HTTPURLResponse.localizedString(forStatusCode: code)
        return "\(String(code)) \(reason.prefix(1).localizedUppercase)\(reason.dropFirst())"
    }

    private func statusTint(_ code: Int) -> Color {
        switch code {
        case 200..<300: Theme.success
        case 300..<400: Theme.roleWrapper
        default: Theme.danger
        }
    }
}
