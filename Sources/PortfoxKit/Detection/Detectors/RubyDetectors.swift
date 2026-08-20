import Foundation

public extension DetectorCatalog {
    /// Rails hands its socket to Puma, which rewrites its own argv via
    /// `setproctitle` to `puma 6.4.2 (tcp://0.0.0.0:3000) [app]`. Every trace of
    /// Rails is gone from the command line, so `.rails` can only be told apart
    /// from a bare Puma process by the Gemfile.
    static let ruby: [any ServiceDetector] = [
        RuleBasedDetector(
            type: .rails,
            threshold: standardThreshold,
            signals: [
                .commandContains("bin/rails", 95),
                .commandContains("rails server", 92),
                .custom("a Rack server, or the bare ruby interpreter, in a project that depends on rails", 90, group: "command") { ctx in
                    let rackServers = ["puma", "rackup", "unicorn", "falcon", "thin", "webrick"]
                    let servedByRack = rackServers.contains { ctx.command.containsToken($0) }
                    guard servedByRack || ctx.executableName == "ruby" else { return false }
                    return ctx.project?.hasDependency("rails") ?? false
                },
                .dependency("rails", 60),
                .defaultPort(3000)
            ]
        ),
        RuleBasedDetector(
            type: .puma,
            threshold: standardThreshold,
            signals: [
                .binPath("puma", 100),
                .commandContains("puma", 95),
                .defaultPorts([9292, 3000])
            ]
        ),
        RuleBasedDetector(
            type: .sinatra,
            threshold: standardThreshold,
            signals: [
                .custom("the bare ruby interpreter in a project that depends on sinatra", 90, group: "command") { ctx in
                    ctx.executableName == "ruby" && (ctx.project?.hasDependency("sinatra") ?? false)
                },
                .dependency("sinatra", 60),
                .defaultPort(4567)
            ]
        ),
        RuleBasedDetector(
            type: .ruby,
            threshold: 20,
            signals: [
                .executableNamed("ruby", 30),
                .defaultPorts([3000, 4567, 9292]),
                // macOS ships /usr/bin/ruby, and classifier rule 2 promotes any
                // detected type past rule 3's systemNoise check for that prefix.
                // A directory rootKind is the fixture default for a script with
                // no real manifest, so only genuine project evidence (a git,
                // workspace or manifest root) rescues a /usr/bin/ruby process.
                .veto("system Ruby at /usr/bin, outside a project with real manifest evidence") { ctx in
                    ctx.executablePath.hasPrefix("/usr/bin/")
                        && (ctx.project == nil || ctx.project?.rootKind == .directory)
                },
                .veto("Ruby bundled inside an app bundle, the IDE-JRE hazard the runtime spec warns about") { ctx in
                    ctx.executablePath.contains(".app/contents/")
                },
                .veto("fluentd, a log forwarder daemon rather than a project's own dev server") { ctx in
                    ctx.command.containsToken("fluentd")
                },
                .veto("gem server, RubyGems' bundled doc server rather than a project's own dev server") { ctx in
                    ctx.command.containsToken("gem") && ctx.command.containsToken("server")
                }
            ]
        )
    ]
}
