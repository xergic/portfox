import Foundation

private extension DetectionContext {
    /// MSBuild and the Roslyn compiler server keep a socket open between builds.
    var isDotNetBuildTooling: Bool {
        Self.buildToolingMarkers.contains(where: command.contains)
    }

    static let buildToolingMarkers = ["msbuild", "vbcscompiler", "build-server"]
    static let editorToolingMarkers = [
        "testhost", "omnisharp", "microsoft.codeanalysis.languageserver", "devenv"
    ]
}

public extension DetectorCatalog {
    /// .NET services. `dotnet run` builds and then execs the *apphost*, a binary
    /// named after the project with no extension at `bin/Debug/net8.0/MyApi`, so
    /// the word `dotnet` never appears in the listener's argv. The build output
    /// path is the identity, and the framework moniker's digits (`net8.0`) defeat
    /// `containsToken`, which is why `isDotNetBuildOutput` uses raw `contains`.
    static let dotNet: [any ServiceDetector] = [
        RuleBasedDetector(
            type: .aspNet,
            threshold: standardThreshold,
            signals: [
                .custom("a .NET build output binary in a web SDK project", 100, group: "command") { ctx in
                    guard ctx.isDotNetBuildOutput, let project = ctx.project else { return false }
                    return project.hasDependency("microsoft.net.sdk.web")
                        || project.hasDependency("microsoft.aspnetcore.app")
                        || project.hasFile(prefix: "appsettings")
                },
                .custom("dotnet exec of an ASP.NET assembly", 90, group: "command") { ctx in
                    ctx.executableName == "dotnet" && ctx.command.contains("aspnetcore")
                },
                .custom("launched by dotnet watch", 85, group: "command") { ctx in
                    ctx.isDotNetBuildOutput && ctx.anyCommandContains("watch")
                },
                .anyDependency(
                    ["microsoft.net.sdk.web", "microsoft.aspnetcore.app", "swashbuckle.aspnetcore"],
                    60
                ),
                .defaultPorts([5000, 5001]),
                .veto("MSBuild and the Roslyn compiler server are build infrastructure") { $0.isDotNetBuildTooling }
            ]
        ),
        RuleBasedDetector(
            type: .dotnet,
            threshold: 20,
            signals: [
                .executableNamed("dotnet", 30),
                .custom("a .NET build output binary", 30, group: "command") { $0.isDotNetBuildOutput },
                .defaultPorts([5000, 5001]),
                .veto("MSBuild and the Roslyn compiler server are build infrastructure") { $0.isDotNetBuildTooling },
                .veto("a test host or an editor language server is not a dev server") { ctx in
                    DetectionContext.editorToolingMarkers.contains(where: ctx.command.contains)
                },
                .vetoAppBundle()
            ]
        )
    ]
}
