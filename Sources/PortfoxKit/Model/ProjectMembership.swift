import Foundation

extension RunningService {
    /// Whether this service's project sits at `root` or inside it. Inside counts,
    /// because a sibling group heading is rooted at the folder holding its
    /// repositories, and loses that root the moment only one of them is running.
    public func isInProject(at root: String) -> Bool {
        guard let path = project?.root.path else { return false }
        return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
