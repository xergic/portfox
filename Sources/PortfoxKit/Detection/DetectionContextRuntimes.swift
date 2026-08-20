import Foundation

/// Runtime shapes that several detectors have to recognise before they may use a
/// raw `contains`.
///
/// `containsToken` refuses a match in the middle of a word, and a digit or a `-`
/// is a word character. That makes it useless against the versioned filenames
/// these ecosystems are built from: `spring-boot-3.2.0.jar`, `net8.0`, `php8.3`.
/// The rows that need those have to fall back to plain `contains`, which is only
/// safe once the runtime itself is confirmed. These properties are that gate.
public extension DetectionContext {
    /// Every JVM service shares one executable, so identity has to come from the
    /// classpath, and a raw classpath search is only safe behind this.
    var isJVM: Bool { executableName == "java" || executableName == "javaw" }

    /// Homebrew, Herd and MAMP all ship a version-suffixed binary, so `php8.3`
    /// and `php-fpm` are both normal. `containsToken("php")` matches neither.
    var isPHP: Bool { executableName.hasPrefix("php") }

    /// `bin/Debug/net8.0/MyApi`. The framework moniker's digits defeat
    /// `containsToken`, and no other toolchain produces this path shape.
    var isDotNetBuildOutput: Bool {
        ["/bin/debug/net", "/bin/release/net"].contains {
            executablePath.contains($0) || command.contains($0)
        }
    }

    /// True when the process runs from inside the resolved project's root.
    /// `executablePath` is lowercased at init, so the root has to be lowercased
    /// too or this never matches a path with a capital in it.
    func runsFromProjectRoot() -> Bool {
        guard let root = project?.root.path.lowercased() else { return false }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return executablePath.hasPrefix(prefix)
    }
}
