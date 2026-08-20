import Foundation

private extension DetectionContext {
    static let cargoOutputPaths = ["/target/debug/", "/target/release/"]
}

public extension DetectorCatalog {
    /// Go and Rust. A compiled binary is named after its module or crate and
    /// carries no runtime evidence at all, so both rows key on build output
    /// paths, which are the only reliable trace.
    ///
    /// Neither row ever names a framework. A crate that depends on axum says
    /// nothing about which of its binaries is listening, so framework detection
    /// is out of scope here by design, not by omission.
    static let compiled: [any ServiceDetector] = [
        RuleBasedDetector(
            type: .go,
            threshold: 40,
            signals: [
                // `go run` compiles into the build cache and executes from there.
                // That path is the only reliable trace of Go on a binary that is
                // otherwise named after the module and nothing else.
                .custom("running from the Go build cache", 90, group: "command") { ctx in
                    ctx.executablePath.contains("/go-build") || ctx.command.contains("/go-build")
                },
                .custom("a Delve debug build", 85, group: "command") { ctx in
                    ctx.executablePath.contains("__debug_bin")
                },
                // `relatedCommands` is a flat bag of ancestors *and* descendants,
                // so a `go run` anywhere in the tree would otherwise claim an
                // unrelated helper the dev server happened to spawn, such as a
                // headless Chrome on its remote debugging port.
                .custom("launched by go run", 80, group: "command") { ctx in
                    ctx.anyCommandContains("go run") && !ctx.isInsideAppBundle
                },
                // Air rebuilds into ./tmp/main and runs it; the binary listens.
                .custom("air live reload is running this binary", 80, group: "command") { ctx in
                    ctx.anyCommandContains("air") && ctx.command.contains("/tmp/")
                },
                .custom("a binary running from inside a Go module", 60, group: "command") { ctx in
                    guard let project = ctx.project, project.hasFile(prefix: "go.mod") else { return false }
                    return ctx.runsFromProjectRoot()
                },
                .defaultPorts([8080, 3000])
            ]
        ),
        RuleBasedDetector(
            type: .rust,
            threshold: 60,
            signals: [
                // Maven also builds into `target/`, but never into a `debug` or
                // `release` child, and its artefact is a jar. Requiring the real
                // Cargo.toml rather than defaulting to true is what keeps a
                // stray build tree from being claimed as Rust.
                .custom("a Cargo build output binary", 90, group: "command") { ctx in
                    guard let project = ctx.project, project.hasFile(prefix: "cargo.toml") else { return false }
                    guard DetectionContext.cargoOutputPaths.contains(where: ctx.executablePath.contains) else {
                        return false
                    }
                    // `target/debug/deps/` holds test harnesses and benchmarks,
                    // which spin up mock servers that are not the user's service.
                    return !ctx.executablePath.contains("/deps/")
                        && !ctx.isInsideAppBundle
                },
                .defaultPorts([8000, 3000]),
                .veto("a jar under target/ is a Maven build, not a Cargo one") { $0.command.contains(".jar") }
            ]
        )
    ]
}
