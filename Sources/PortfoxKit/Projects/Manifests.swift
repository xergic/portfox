import Foundation

/// Facts read out of one project manifest file.
public struct ManifestData: Hashable, Sendable {
    public var name: String?
    /// The project's own version, from `package.json`, `pyproject.toml` and so on.
    public var version: String?
    /// Lowercased union of dependencies, devDependencies and peerDependencies.
    public var dependencies: Set<String>
    public var scripts: [String: String]
    /// True when a root package.json declares a `workspaces` field.
    public var declaresWorkspaces: Bool
    /// Path of a project icon declared by the manifest, relative to the manifest directory.
    public var declaredIconPath: String?

    public init(
        name: String? = nil,
        version: String? = nil,
        dependencies: Set<String> = [],
        scripts: [String: String] = [:],
        declaresWorkspaces: Bool = false,
        declaredIconPath: String? = nil
    ) {
        self.name = name
        self.version = version
        self.dependencies = dependencies
        self.scripts = scripts
        self.declaresWorkspaces = declaresWorkspaces
        self.declaredIconPath = declaredIconPath
    }

    public static let empty = ManifestData()

    public var isEmpty: Bool {
        name == nil && version == nil && dependencies.isEmpty && scripts.isEmpty && !declaresWorkspaces && declaredIconPath == nil
    }

    /// Combines a nearer manifest with one further up the tree. Nearer wins on
    /// scalar fields, collections merge.
    public func merging(parent: ManifestData) -> ManifestData {
        ManifestData(
            name: name ?? parent.name,
            version: version ?? parent.version,
            dependencies: dependencies.union(parent.dependencies),
            scripts: scripts.merging(parent.scripts) { near, _ in near },
            declaresWorkspaces: declaresWorkspaces || parent.declaresWorkspaces,
            declaredIconPath: declaredIconPath ?? parent.declaredIconPath
        )
    }
}

/// Parses project manifests without executing anything. Dynamic JavaScript and
/// TypeScript configs are deliberately not evaluated, per spec section 9.
public enum ManifestReader {
    /// Reads `package.json` from `directory`.
    public static func packageJSON(in directory: URL) -> ManifestData? {
        guard let json = readJSONObject(directory.appendingPathComponent("package.json")) else { return nil }

        var dependencies: Set<String> = []
        for key in ["dependencies", "devDependencies", "peerDependencies"] {
            dependencies.formUnion(dependencyNames(in: json[key]))
        }

        var declaresWorkspaces = false
        if let workspaces = json["workspaces"] {
            declaresWorkspaces = (workspaces as? [Any]) != nil || (workspaces as? [String: Any]) != nil
        }

        return ManifestData(
            name: json["name"] as? String,
            version: json["version"] as? String,
            dependencies: dependencies,
            scripts: json["scripts"] as? [String: String] ?? [:],
            declaresWorkspaces: declaresWorkspaces
        )
    }

    /// Reads Expo config from `app.json` or `app.config.json` in `directory`.
    /// `app.config.js` and `app.config.ts` are not evaluated.
    public static func expoConfig(in directory: URL) -> ManifestData? {
        let candidates = ["app.json", "app.config.json"]
        guard let json = candidates.lazy.compactMap({ readJSONObject(directory.appendingPathComponent($0)) }).first else {
            return nil
        }

        let expo = json["expo"] as? [String: Any]
        guard expo != nil || json["name"] != nil else { return nil }

        let source = expo ?? json
        return ManifestData(
            name: source["name"] as? String,
            version: source["version"] as? String,
            dependencies: expo != nil ? ["expo"] : [],
            declaredIconPath: source["icon"] as? String
        )
    }

    /// Reads `pyproject.toml` well enough to get the project name and its
    /// dependency names. Not a general TOML parser.
    public static func pyproject(in directory: URL) -> ManifestData? {
        guard let text = readText(directory.appendingPathComponent("pyproject.toml")) else { return nil }

        let sections = tomlSections(in: text)
        let projectOrPoetrySection = sections["project"] ?? sections["tool.poetry"] ?? ""
        let name = tomlString(key: "name", in: projectOrPoetrySection)
        let version = tomlString(key: "version", in: projectOrPoetrySection)

        var dependencies: Set<String> = []
        if let projectSection = sections["project"] {
            dependencies.formUnion(tomlDependencyArray(key: "dependencies", in: projectSection))
        }
        if let poetryDeps = sections["tool.poetry.dependencies"] {
            dependencies.formUnion(tomlTableKeys(in: poetryDeps))
        }

        guard name != nil || !dependencies.isEmpty else { return nil }
        return ManifestData(name: name, version: version, dependencies: dependencies)
    }

    /// Reads dependency names out of `requirements.txt`.
    public static func requirementsTxt(in directory: URL) -> ManifestData? {
        guard let text = readText(directory.appendingPathComponent("requirements.txt")) else { return nil }

        let dependencies = text.split(separator: "\n").compactMap { line -> String? in
            requirementName(String(line))
        }
        guard !dependencies.isEmpty else { return nil }
        return ManifestData(dependencies: Set(dependencies))
    }

    /// Reads the project identifier and declared coordinates from `pom.xml`.
    public static func pomXML(in directory: URL) -> ManifestData? {
        guard let text = readText(directory.appendingPathComponent("pom.xml")) else { return nil }

        let artifactIDs = regexMatches(#"<artifactId>\s*([^<]+?)\s*</artifactId>"#, in: text)
        let groupIDs = regexMatches(#"<groupId>\s*([^<]+?)\s*</groupId>"#, in: text)
        let dependencies = Set((artifactIDs + groupIDs).map { $0.lowercased() })
        guard !dependencies.isEmpty else { return nil }
        return ManifestData(name: artifactIDs.first, dependencies: dependencies)
    }

    /// Reads Gradle dependencies, plugins and the root project name without evaluating build scripts.
    public static func gradleBuild(in directory: URL) -> ManifestData? {
        let buildFiles = ["build.gradle", "build.gradle.kts"]
        let settingsFiles = ["settings.gradle", "settings.gradle.kts"]
        let buildText = buildFiles.compactMap { readText(directory.appendingPathComponent($0)) }.joined(separator: "\n")
        let settingsText = settingsFiles.compactMap { readText(directory.appendingPathComponent($0)) }.joined(separator: "\n")
        guard !buildText.isEmpty || !settingsText.isEmpty else { return nil }

        var dependencies: Set<String> = []
        for coordinate in regexMatches(#"[\"']([A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+)(?::[^\"']+)?[\"']"#, in: buildText) {
            let parts = coordinate.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            dependencies.formUnion([parts[0].lowercased(), parts[1].lowercased(), coordinate.lowercased()])
        }
        dependencies.formUnion(regexMatches(#"\bid\s*\(\s*[\"']([^\"']+)[\"']\s*\)"#, in: buildText).map { $0.lowercased() })

        let name = regexMatches(#"\brootProject\.name\s*=\s*[\"']([^\"']+)[\"']"#, in: settingsText).first
        return ManifestData(name: name, dependencies: dependencies)
    }

    /// Reads gem names from `Gemfile`.
    public static func gemfile(in directory: URL) -> ManifestData? {
        guard let text = readText(directory.appendingPathComponent("Gemfile")) else { return nil }
        let dependencies = Set(regexMatches(#"\bgem\s+[\"']([^\"']+)[\"']"#, in: text).map { $0.lowercased() })
        return dependencies.isEmpty ? nil : ManifestData(dependencies: dependencies)
    }

    /// Reads Composer package names from its dependency sections.
    public static func composerJSON(in directory: URL) -> ManifestData? {
        guard let json = readJSONObject(directory.appendingPathComponent("composer.json")) else { return nil }

        var dependencies: Set<String> = []
        for key in ["require", "require-dev"] {
            for package in dependencyNames(in: json[key]) {
                dependencies.insert(package)
                if let vendor = package.split(separator: "/", maxSplits: 1).first, !vendor.isEmpty {
                    dependencies.insert(vendor.lowercased())
                }
            }
        }
        let name = json["name"] as? String
        guard name != nil || !dependencies.isEmpty else { return nil }
        return ManifestData(name: name, dependencies: dependencies)
    }

    /// Reads NuGet references from project files in `directory`.
    public static func csproj(in directory: URL, entries: Set<String>? = nil) -> ManifestData? {
        let names = entries ?? directoryEntries(at: directory)
        let projectFiles = names.filter { $0.hasSuffix(".csproj") || $0.hasSuffix(".fsproj") }
        guard !projectFiles.isEmpty else { return nil }

        var dependencies: Set<String> = []
        for file in projectFiles {
            guard let text = readText(directory.appendingPathComponent(file)) else { continue }
            let packageReferences = regexMatches(
                #"<PackageReference\b[^>]*\bInclude\s*=\s*[\"']([^\"']+)[\"']"#,
                in: text
            )
            dependencies.formUnion(packageReferences.map { $0.lowercased() })
            if text.range(of: #"<Project\b[^>]*\bSdk\s*=\s*[\"']Microsoft\.NET\.Sdk\.Web[\"']"#, options: .regularExpression) != nil {
                dependencies.insert("microsoft.net.sdk.web")
            }
        }
        return ManifestData(dependencies: dependencies)
    }

    /// Reads package metadata and dependency keys from `Cargo.toml`.
    public static func cargoTOML(in directory: URL) -> ManifestData? {
        guard let text = readText(directory.appendingPathComponent("Cargo.toml")) else { return nil }
        let sections = tomlSections(in: text)
        let package = sections["package"] ?? ""
        let name = tomlString(key: "name", in: package)
        let version = tomlString(key: "version", in: package)
        let dependencies = sections["dependencies"].map { tomlTableKeys(in: $0) } ?? []
        guard name != nil || version != nil || !dependencies.isEmpty else { return nil }
        return ManifestData(name: name, version: version, dependencies: dependencies)
    }

    /// Reads the module path from `go.mod`.
    public static func goMod(in directory: URL) -> ManifestData? {
        guard let text = readText(directory.appendingPathComponent("go.mod")) else { return nil }
        guard let module = regexMatches(#"(?m)^\s*module\s+([^\s]+)"#, in: text).first else { return nil }
        return ManifestData(name: module.split(separator: "/").last.map(String.init))
    }

    /// Reads project metadata and import-map keys from Deno configuration.
    public static func denoJSON(in directory: URL) -> ManifestData? {
        let candidates = ["deno.json", "deno.jsonc"]
        guard let json = candidates.lazy.compactMap({ readJSONObject(directory.appendingPathComponent($0)) }).first else { return nil }
        let dependencies = dependencyNames(in: json["imports"])
        let name = json["name"] as? String
        let version = json["version"] as? String
        guard name != nil || version != nil || !dependencies.isEmpty else { return nil }
        return ManifestData(name: name, version: version, dependencies: dependencies)
    }

    /// Every manifest recognised in `directory`, merged.
    public static func read(in directory: URL) -> ManifestData {
        read(in: directory, entries: nil)
    }

    /// Every manifest recognised in `directory`, merged using known directory entries when available.
    public static func read(in directory: URL, entries: Set<String>? = nil) -> ManifestData {
        let readers = [
            packageJSON, expoConfig, pyproject, requirementsTxt, pomXML, gradleBuild,
            gemfile, composerJSON, cargoTOML, goMod, denoJSON
        ]
        var manifest = readers.compactMap { $0(directory) }.reduce(ManifestData.empty) { $0.merging(parent: $1) }
        if let csproj = csproj(in: directory, entries: entries) {
            manifest = manifest.merging(parent: csproj)
        }
        return manifest
    }

    // MARK: - JSON helpers

    private static func readJSONObject(_ url: URL) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func dependencyNames(in value: Any?) -> Set<String> {
        guard let dict = value as? [String: Any] else { return [] }
        return Set(dict.keys.map { $0.lowercased() })
    }

    private static func directoryEntries(at directory: URL) -> Set<String> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return Set(names)
    }

    // MARK: - Text helpers

    private static func readText(_ url: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func regexMatches(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let capturedRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[capturedRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func requirementName(_ rawLine: String) -> String? {
        var line = rawLine
        if let commentIndex = line.firstIndex(of: "#") {
            line = String(line[..<commentIndex])
        }
        line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("-") else { return nil }

        let specifierCharacters = CharacterSet(charactersIn: "=<>!~; ")
        let name = line
            .components(separatedBy: specifierCharacters)
            .first { !$0.isEmpty } ?? line
        let withoutExtras = name.components(separatedBy: "[").first ?? name
        return withoutExtras.isEmpty ? nil : withoutExtras.lowercased()
    }

    // MARK: - TOML helpers

    /// Splits a `.toml` file into `[section.name]` bodies, keyed by the dotted
    /// section name without brackets. Not a general parser: array-of-tables and
    /// nested inline tables are not supported, which is fine for the manifests
    /// this reads.
    private static func tomlSections(in text: String) -> [String: String] {
        var sections: [String: String] = [:]
        var currentKey = ""
        var currentBody = ""

        func flush() {
            guard !currentKey.isEmpty else { return }
            sections[currentKey] = currentBody
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                flush()
                currentKey = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                currentBody = ""
            } else {
                currentBody += rawLine + "\n"
            }
        }
        flush()
        return sections
    }

    private static func tomlString(key: String, in section: String) -> String? {
        guard let range = section.range(of: #"(?m)^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*"(.*?)""#,
                                          options: .regularExpression) else { return nil }
        let match = String(section[range])
        guard let quoteStart = match.firstIndex(of: "\""), let quoteEnd = match.lastIndex(of: "\""), quoteStart < quoteEnd else {
            return nil
        }
        return String(match[match.index(after: quoteStart)..<quoteEnd])
    }

    /// Scans from the opening `[` to its matching `]`, tracking bracket depth
    /// only outside quotes so an extras marker like `uvicorn[standard]` inside a
    /// quoted entry does not look like the end of the array.
    private static func tomlDependencyArray(key: String, in section: String) -> Set<String> {
        guard let startRange = section.range(
            of: #"(?m)^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*\["#,
            options: .regularExpression
        ) else {
            return []
        }

        var names: Set<String> = []
        var current = ""
        var insideQuotes = false
        var quoteChar: Character = "\""
        var depth = 1
        var index = startRange.upperBound

        while index < section.endIndex, depth > 0 {
            let character = section[index]
            if insideQuotes {
                if character == quoteChar {
                    insideQuotes = false
                    if let name = requirementName(current) { names.insert(name) }
                    current = ""
                } else {
                    current.append(character)
                }
            } else {
                switch character {
                case "\"", "'":
                    insideQuotes = true
                    quoteChar = character
                case "[":
                    depth += 1
                case "]":
                    depth -= 1
                default:
                    break
                }
            }
            index = section.index(after: index)
        }
        return names
    }

    private static func tomlTableKeys(in section: String) -> Set<String> {
        var keys: Set<String> = []
        for rawLine in section.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let equalsIndex = line.firstIndex(of: "=") else { continue }
            let key = line[..<equalsIndex].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            keys.insert(key.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).lowercased())
        }
        return keys
    }
}
