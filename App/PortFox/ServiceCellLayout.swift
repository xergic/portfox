import Foundation

/// Which fact leads a service cell. Applied in both the popover and the
/// dashboard, so a project-first user never sees a framework-first row.
enum ServiceCellLayout: String, CaseIterable, Sendable {
    case serviceFirst
    case projectFirst

    var displayName: String {
        switch self {
        case .serviceFirst: "Service"
        case .projectFirst: "Project"
        }
    }
}
