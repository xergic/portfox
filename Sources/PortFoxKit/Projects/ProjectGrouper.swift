import Foundation

/// A project heading in the popover, with the services that belong to it.
public struct ProjectGroup: Identifiable, Sendable {
    public var id: String { project.id }

    public let project: Project
    public let services: [RunningService]

    public init(project: Project, services: [RunningService]) {
        self.project = project
        self.services = services
    }
}

/// Turns a flat service list into project headings.
///
/// Beyond the obvious "same project root" grouping, this folds sibling
/// repositories together. Four separate git repos in `~/Work/Wishfox` are one
/// mental project even though they are four roots, so when several roots share an
/// immediate parent that is not itself a code collection root, the parent becomes
/// the heading.
public struct ProjectGrouper: Sendable {
    private let groupSiblingRepositories: Bool
    /// Directories that hold many unrelated projects and must never become a
    /// heading themselves, such as `~/Projects` or `~/Work`.
    private let codeCollectionRoots: Set<String>

    public init(
        groupSiblingRepositories: Bool = true,
        codeCollectionRoots: Set<String> = ProjectGrouper.defaultCodeCollectionRoots()
    ) {
        self.groupSiblingRepositories = groupSiblingRepositories
        self.codeCollectionRoots = codeCollectionRoots
    }

    public static func defaultCodeCollectionRoots() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let names = [
            "Code", "Coding", "Projects", "Project", "Work", "dev", "Dev", "Developer",
            "src", "Sites", "repos", "Repos", "git", "GitHub", "Documents", "Desktop", "Downloads"
        ]
        return Set(names.map { "\(home)/\($0)" } + [home, "/", "/tmp", "/opt", "/usr/local", "/opt/homebrew"])
    }

    /// Groups services that have a project. Services without one are the caller's
    /// problem, they belong in the infrastructure section.
    public func group(_ services: [RunningService]) -> [ProjectGroup] { [] }
}
