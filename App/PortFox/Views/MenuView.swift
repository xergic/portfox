import PortFoxKit
import SwiftUI

struct MenuView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

    /// ImageRenderer cannot lay out a ScrollView, so the snapshot mode renders
    /// the same content unscrolled.
    var scrolls = true
    /// Snapshot rendering forces the first row of the first group into hover.
    var forcesHover = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.separator)

            if state.result.services.isEmpty {
                emptyState
            } else {
                list
            }

            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: Theme.Metrics.popoverWidth)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .onAppear { state.popoverDidAppear() }
        .onDisappear { state.popoverDidDisappear() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(.menuBarFox)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
                .foregroundStyle(Color(red: 0.98, green: 0.55, blue: 0.24))

            Text("PortFox")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.primaryText)

            Text(String(state.serviceCount))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.pill)
                )

            Spacer()

            IconButton(symbol: "arrow.trianglehead.2.clockwise", help: "Refresh") {
                Task { await state.refresh() }
            }
            .rotationEffect(.degrees(state.isRefreshing ? 360 : 0))
            .animation(
                state.isRefreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                value: state.isRefreshing
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var list: some View {
        if scrolls {
            ScrollView { listContent }
                .frame(maxHeight: Theme.Metrics.maximumListHeight)
                .scrollBounceBehavior(.basedOnSize)
        } else {
            listContent
        }
    }

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 10) {
                if let error = state.lastError {
                    ErrorBanner(message: error)
                }

                ForEach(state.result.groups) { group in
                    ProjectSectionView(group: group, forcesHover: forcesHover)
                }

                if !state.result.standalone.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "INFRASTRUCTURE & DAEMONS")
                        ForEach(state.result.standalone) { service in
                            ServiceRowView(service: service, forcedHover: forcesHover)
                        }
                    }
                }

                if !ungrouped.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "OTHER LISTENERS")
                        ForEach(ungrouped) { service in
                            ServiceRowView(service: service)
                        }
                    }
                }
            }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    /// Services with a project that the grouper did not place, plus anything the
    /// split missed. Showing them beats silently dropping a running server.
    private var ungrouped: [RunningService] {
        let placed = Set(
            state.result.groups.flatMap { $0.services.map(\.id) } + state.result.standalone.map(\.id)
        )
        return state.result.services.filter { !placed.contains($0.id) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 22))
                .foregroundStyle(Theme.tertiaryText)
            Text("No development services running")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            if let error = state.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                openSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Settings…")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(Theme.danger)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.danger.opacity(0.12))
            )
    }
}
