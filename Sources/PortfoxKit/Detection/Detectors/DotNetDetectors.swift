import Foundation

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
                .veto("MSBuild and the Roslyn compiler server are build infrastructure") { ctx in
                    ["msbuild", "vbcscompiler", "build-server"].contains(where: ctx.command.contains)
                }
            ]
        ),
        RuleBasedDetector(
            type: .dotnet,
            threshold: 20,
            signals: [
                .executableNamed("dotnet", 30),
                .custom("a .NET build output binary", 30, group: "command") { $0.isDotNetBuildOutput },
                .defaultPorts([5000, 5001]),
                .veto("MSBuild and the Roslyn compiler server are build infrastructure") { ctx in
                    ["msbuild", "vbcscompiler", "build-server"].contains(where: ctx.command.contains)
                },
                .veto("a test host or an editor language server is not a dev server") { ctx in
                    ["testhost", "omnisharp", "microsoft.codeanalysis.languageserver", "devenv"]
                        .contains(where: ctx.command.contains)
                },
                // Detection outranks the classifier's bundle rule, so Rider's
                // bundled backend would otherwise be promoted to a dev service.
                .veto("a .NET runtime inside an application bundle belongs to that app") { ctx in
                    ctx.executablePath.contains(".app/contents/")
                }
            ]
        )
    ]
}
