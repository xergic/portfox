import Testing
@testable import PortfoxKit

@Suite("ruby detectors")
struct RubyDetectorsTests {
    let engine = DetectionEngine(detectors: DetectorCatalog.ruby + DetectorCatalog.nodeEcosystem)

    @Test("Puma's rewritten argv in a Rails project is reported as Rails")
    func pumaArgvInRailsProjectIsRails() {
        let context = DetectionFixture.context(
            command: "puma 6.4.2 (tcp://0.0.0.0:3000) [shop]",
            executablePath: "/Users/me/.rbenv/versions/3.3.0/bin/ruby",
            dependencies: ["rails", "puma"],
            ports: [3000]
        )

        #expect(engine.detect(context).type == .rails)
    }

    @Test("Rails wins on score, not on the specificity tie-break")
    func railsBeatsPumaOnScore() {
        let context = DetectionFixture.context(
            command: "puma 6.4.2 (tcp://0.0.0.0:3000) [shop]",
            executablePath: "/Users/me/.rbenv/versions/3.3.0/bin/ruby",
            dependencies: ["rails", "puma"],
            ports: [3000]
        )

        let matches = engine.allMatches(context)
        let rails = matches.first { $0.type == .rails }
        let puma = matches.first { $0.type == .puma }

        #expect(rails?.score == 160)
        #expect(puma?.score == 105)
        #expect(engine.detect(context).type == .rails)
    }

    @Test("the identical Puma argv with no Rails gem is reported as Puma, not Rails")
    func pumaArgvWithoutRailsGemIsPuma() {
        let context = DetectionFixture.context(
            command: "puma 6.4.2 (tcp://0.0.0.0:3000) [shop]",
            executablePath: "/Users/me/.rbenv/versions/3.3.0/bin/ruby",
            dependencies: ["puma"],
            ports: [3000]
        )

        let type = engine.detect(context).type
        #expect(type == .puma)
        #expect(type != .rails)
    }

    @Test("bin/rails server is unambiguous Rails")
    func binRailsServerIsRails() {
        let context = DetectionFixture.context(
            command: "bin/rails server -p 3000",
            executablePath: "/Users/me/.rbenv/versions/3.3.0/bin/ruby",
            ports: [3000]
        )

        #expect(engine.detect(context).type == .rails)
    }

    @Test("a bare ruby script in a real project falls back to generic Ruby")
    func bareRubyScriptInProjectIsRuby() {
        let context = DetectionFixture.context(
            command: "ruby script.rb",
            executablePath: "/Users/me/.rbenv/versions/3.3.0/bin/ruby",
            projectFiles: ["Gemfile", "script.rb"],
            ports: [3000]
        )

        #expect(engine.detect(context).type == .ruby)
    }

    @Test("system Ruby at /usr/bin with no project is not reported at all")
    func systemRubyWithNoProjectIsNotRuby() {
        let context = DetectionFixture.context(
            command: "ruby -run -e httpd . -p 3000",
            executablePath: "/usr/bin/ruby",
            ports: [3000]
        )

        #expect(engine.detect(context).type != .ruby)
    }

    @Test("Sinatra happy path")
    func sinatraHappyPath() {
        let context = DetectionFixture.context(
            command: "ruby app.rb",
            executablePath: "/Users/me/.rbenv/versions/3.3.0/bin/ruby",
            dependencies: ["sinatra"],
            ports: [4567]
        )

        #expect(engine.detect(context).type == .sinatra)
    }

    @Test("fluentd on the ruby interpreter is not the generic Ruby fallback")
    func fluentdIsNotRuby() {
        let context = DetectionFixture.context(
            command: "ruby /usr/local/bin/fluentd -c fluent.conf",
            executablePath: "/Users/me/.rbenv/versions/3.3.0/bin/ruby",
            ports: [9292]
        )

        #expect(engine.detect(context).type != .ruby)
    }

    @Test("gem server is not the generic Ruby fallback")
    func gemServerIsNotRuby() {
        let context = DetectionFixture.context(
            command: "ruby /usr/bin/gem server",
            executablePath: "/Users/me/.rbenv/versions/3.3.0/bin/ruby",
            ports: [8808]
        )

        #expect(engine.detect(context).type != .ruby)
    }

    @Test("Node on Rails' own port is reported as Node, never Rails or Ruby")
    func nodeOnPort3000IsNotRailsOrRuby() {
        let context = DetectionFixture.context(
            command: "node dist/main.js",
            executablePath: "/usr/local/bin/node",
            projectFiles: ["package.json"],
            ports: [3000]
        )

        let type = engine.detect(context).type
        #expect(type == .node)
        #expect(type != .rails)
        #expect(type != .ruby)
    }

    @Test("a directory named rails-demo holding a Node server is not Rails evidence")
    func railsNamedDirectoryIsNotEvidence() {
        let context = DetectionFixture.context(
            command: "node server.js",
            executablePath: "/usr/local/bin/node",
            projectFiles: ["rails-demo", "package.json"],
            ports: [3000]
        )

        #expect(engine.detect(context).type == .node)
    }
}
