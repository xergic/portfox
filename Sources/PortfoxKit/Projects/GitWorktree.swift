import Foundation

/// A linked git worktree, read from the `.git` file at its top.
///
/// A main checkout has a `.git` directory. A linked worktree has a `.git` file
/// pointing into `<main>/.git/worktrees/<name>`. A submodule has a `.git` file
/// too, pointing into `.git/modules/`, which is why the path is checked rather
/// than the file merely existing.
enum GitWorktree {
    /// The branch, or the worktree's name when HEAD is detached, as an agent's
    /// worktree often is. Nil for anything that is not a linked worktree.
    static func label(of checkout: URL) -> String? {
        let pointer = checkout.appendingPathComponent(".git")
        guard let contents = try? String(contentsOf: pointer, encoding: .utf8),
              let line = contents.split(separator: "\n").first, line.hasPrefix("gitdir:")
        else { return nil }

        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let gitDirectory = URL(fileURLWithPath: path, relativeTo: checkout).standardizedFileURL
        guard gitDirectory.deletingLastPathComponent().lastPathComponent == "worktrees" else { return nil }

        let head = (try? String(contentsOf: gitDirectory.appendingPathComponent("HEAD"), encoding: .utf8)) ?? ""
        let branchPrefix = "ref: refs/heads/"
        let ref = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return ref.hasPrefix(branchPrefix) ? String(ref.dropFirst(branchPrefix.count)) : gitDirectory.lastPathComponent
    }
}
