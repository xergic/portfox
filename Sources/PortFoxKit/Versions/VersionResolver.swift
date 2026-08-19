import Foundation

/// Finds the version of the software a service is running.
///
/// Three sources, cheapest first. The executable path often encodes the version
/// outright, a framework's version sits in its own `package.json`, and only as a
/// last resort is the binary asked directly.
public actor VersionResolver {
    private var cache: [String: String?] = [:]

    /// npm package name(s) for a framework's own version, in priority order.
    /// Types without an npm package have no entry and never report a framework version.
    private static let frameworkPackages: [ServiceType: [String]] = [
        .vite: ["vite"],
        .nextJS: ["next"],
        .nuxt: ["nuxt"],
        .astro: ["astro"],
        .svelteKit: ["@sveltejs/kit"],
        .remix: ["react-router", "@remix-run/dev"],
        .angular: ["@angular/core"],
        .nestJS: ["@nestjs/core"],
        .storybook: ["storybook"],
        .expo: ["expo"],
        .metro: ["metro"],
        .wrangler: ["wrangler"]
    ]

    /// Types whose binary is safe to ask for its own version. Anything outside
    /// this set, notably `.unknown`, is never spawned.
    private static let runtimeSpawnTypes: Set<ServiceType> = [
        .node, .bun, .deno, .python, .postgres, .redis, .mysql, .mongodb
    ]

    /// Last path component the executable must match before it is spawned, so a
    /// misclassified path can never run an arbitrary binary.
    private static let runtimeSpawnAllowlist: Set<String> = [
        "node", "bun", "deno", "python", "python3", "postgres", "redis-server", "mysqld", "mongod"
    ]

    public init() {}

    /// Version to show beside the service name, or nil when nothing reliable was
    /// found. Never blocks on an unknown binary.
    public func version(for service: RunningService) async -> String? {
        let listener = service.listenerProcess
        if let framework = frameworkVersion(type: service.type, project: service.project, command: listener.command) {
            return framework
        }
        // `runtimeVersion` returns what the path or the binary said. Normalising
        // happens here so both sources reach the UI in the same shape, and a
        // Node reporting 24.16.0 shows as 24.16.
        let runtime = await runtimeVersion(type: service.type, executablePath: listener.resolvedExecutablePath)
        return runtime.flatMap(Self.display)
    }

    /// Version of the framework package itself, read from `node_modules`.
    public func frameworkVersion(type: ServiceType, project: ProjectSnapshot?, command: String) -> String? {
        guard let packages = Self.frameworkPackages[type] else { return nil }

        for package in packages {
            if let raw = Self.pnpmStoreVersion(of: package, in: command) {
                return Self.display(raw)
            }
        }

        guard let project else { return nil }
        for package in packages {
            let raw = Self.packageJSONVersion(of: package, in: project.serviceDirectory)
                ?? Self.packageJSONVersion(of: package, in: project.root)
            if let raw {
                return Self.display(raw)
            }
        }
        return nil
    }

    /// Version of the interpreter or daemon behind `executablePath`.
    public func runtimeVersion(type: ServiceType, executablePath: String?) async -> String? {
        guard let executablePath, !executablePath.isEmpty else { return nil }
        if let cached = cache[executablePath] { return cached }

        if let fromPath = Self.versionFromPath(executablePath) {
            cache.updateValue(fromPath, forKey: executablePath)
            return fromPath
        }

        guard Self.runtimeSpawnTypes.contains(type) else {
            cache.updateValue(nil, forKey: executablePath)
            return nil
        }
        let executableName = (executablePath as NSString).lastPathComponent
        guard Self.runtimeSpawnAllowlist.contains(executableName) else {
            cache.updateValue(nil, forKey: executablePath)
            return nil
        }

        let result = await Self.spawnedVersion(executablePath: executablePath)
        cache.updateValue(result, forKey: executablePath)
        return result
    }

    /// Trims a reported version to what is worth showing. `v24.16.0` becomes
    /// `24.16`, because a trailing zero patch is noise, while `4.5.2` is kept.
    public static func display(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        guard let range = text.range(of: #"\d+(\.\d+){0,2}"#, options: .regularExpression) else { return nil }

        var components = text[range].split(separator: ".").map(String.init)
        if components.count > 1, components.last == "0" {
            components.removeLast()
        }
        return components.joined(separator: ".")
    }

    public func invalidate() {
        cache.removeAll()
    }

    // MARK: - Framework version sources

    /// Finds `<package>@<version>` inside a pnpm store path, where sibling
    /// dependencies are encoded the same way and scoped packages use `+`
    /// instead of `/`. A boundary of `/`, `+` or the string start is required
    /// before the package name so `nuxt@4.5.2` is never matched inside an
    /// unrelated `@babel+plugin-syntax-jsx@7.29.7` segment.
    private static func pnpmStoreVersion(of package: String, in command: String) -> String? {
        let encoded = NSRegularExpression.escapedPattern(for: package.replacingOccurrences(of: "/", with: "+"))
        guard let regex = try? NSRegularExpression(pattern: "(?:^|[/+])" + encoded + #"@(\d[\d.]*)"#) else { return nil }

        let range = NSRange(command.startIndex..., in: command)
        guard let match = regex.firstMatch(in: command, range: range),
              let versionRange = Range(match.range(at: 1), in: command) else { return nil }
        return String(command[versionRange])
    }

    private static func packageJSONVersion(of package: String, in directory: URL) -> String? {
        let url = directory.appendingPathComponent("node_modules/\(package)/package.json")
        guard let data = FileManager.default.contents(atPath: url.path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }

    // MARK: - Runtime version sources

    /// Reads a version straight out of an install path, such as an nvm or fnm
    /// node folder, a Homebrew `<formula>@<version>` cellar, or a DBngin
    /// version directory. Checked from the executable outward, since the
    /// version component sits closest to the binary.
    private static func versionFromPath(_ executablePath: String) -> String? {
        let components = executablePath.split(separator: "/").map(String.init)
        for component in components.reversed() {
            if let atIndex = component.firstIndex(of: "@") {
                let suffix = String(component[component.index(after: atIndex)...])
                if isVersionLike(suffix) { return suffix }
            }

            var candidate = component
            if candidate.hasPrefix("v") || candidate.hasPrefix("V") {
                candidate.removeFirst()
            }
            if isVersionLike(candidate) { return candidate }
        }
        return nil
    }

    private static func isVersionLike(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil
    }

    /// Runs `<executablePath> --version` with a hard 1 second timeout. The
    /// continuation always resumes, from whichever of the timeout or the
    /// termination handler fires first, so an unresponsive binary can never
    /// hang a refresh.
    private static func spawnedVersion(executablePath: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["--version"]
            process.standardInput = FileHandle.nullDevice

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let finisher = SpawnFinisher(continuation: continuation)

            process.terminationHandler = { _ in
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
                    ?? String(data: errorData, encoding: .utf8)
                finisher.finish(output.flatMap(display))
            }

            do {
                try process.run()
            } catch {
                finisher.finish(nil)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { process.terminate() }
                finisher.finish(nil)
            }
        }
    }

    /// Resumes a spawn continuation exactly once, whichever of the termination
    /// handler or the timeout fires first.
    private final class SpawnFinisher: @unchecked Sendable {
        private let continuation: CheckedContinuation<String?, Never>
        private let lock = NSLock()
        private var finished = false

        init(continuation: CheckedContinuation<String?, Never>) {
            self.continuation = continuation
        }

        func finish(_ value: String?) {
            lock.lock()
            let alreadyFinished = finished
            finished = true
            lock.unlock()
            guard !alreadyFinished else { return }
            continuation.resume(returning: value)
        }
    }
}
