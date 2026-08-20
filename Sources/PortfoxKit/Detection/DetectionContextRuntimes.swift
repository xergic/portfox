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

    /// Homebrew, Herd and MAMP all ship a version-suffixed binary, so `php8.3`,
    /// `php8.4` and `php-fpm` are all normal. `containsToken("php")` matches none
    /// of them, because digits and `-` are word characters.
    ///
    /// A bare `hasPrefix("php")` is too loose in the other direction: it also
    /// claims `phpstorm`, which is an IDE, not an interpreter. So the tail after
    /// `php` has to look like a version or an SAPI suffix.
    var isPHP: Bool {
        guard executableName.hasPrefix("php") else { return false }
        let tail = executableName.dropFirst(3)
        if tail.isEmpty { return true }
        if ["-fpm", "-cgi", "-cli"].contains(String(tail)) { return true }
        return tail.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

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

    /// JVM processes that listen on a port but are never the user's service:
    /// build daemons, test forks, debug transports and editor language servers.
    ///
    /// Every JVM detector has to apply this, not just the generic `java` row. A
    /// veto only disqualifies the detector that declares it, so without this a
    /// Surefire fork whose test classpath happens to contain `spring-boot-test`
    /// would be reported as a running Spring Boot application.
    ///
    /// This is a denylist over an unbounded set, so it will need entries added.
    /// What actually carries the weight is `ListenerClassifier`'s ephemeral-port
    /// rule, which hides anything bound only above 49152 before detection is even
    /// consulted. This list is for the tooling that picks a low fixed port.
    var isJVMTooling: Bool {
        let markers = [
            // Gradle
            "org.gradle.launcher.daemon", "org.gradle.process.internal.worker", "gradleworkermain",
            // Maven, and its test forks
            "org.apache.maven.surefire.booter", "org.codehaus.plexus.classworlds.launcher",
            // Kotlin, Scala, sbt
            "kotlin-daemon", "org.jetbrains.kotlin.daemon", "scala.tools.nsc",
            "xsbt.boot.boot", "sbt.forkmain", "bloop",
            // JetBrains
            "com.intellij", "org.jetbrains.jps", "idea_rt", "nailgun",
            // Eclipse and the VS Code Java extensions
            "org.eclipse.equinox.launcher", "org.eclipse.jdt.ls", "com.microsoft.java.debug",
            // Test runners
            "junitplatform.consolelauncher", "org.testng.remote",
            // Bazel
            "com.google.devtools.build"
        ]
        if markers.contains(where: command.contains) { return true }
        // A debug or management transport is the only listener these open.
        return command.contains("-agentlib:jdwp") || command.contains("com.sun.management.jmxremote")
    }
}
