import Testing
@testable import PortfoxKit

/// Port 5000 is the contested one. Flask has claimed it for years, ASP.NET
/// claims it by default, and macOS AirPlay Receiver squats on it with no command
/// evidence for either. All three cases are asserted below.
@Suite(".NET detectors")
struct DotNetDetectorsTests {
    private let engine = DetectionEngine(detectors: DetectorCatalog.dotNet + DetectorCatalog.python)

    @Test("the apphost of a web SDK project is ASP.NET Core")
    func apphostInWebProject() {
        // `dotnet run` execs a binary named after the project, so nothing on the
        // command line says .NET at all. The build output path is the identity.
        let context = DetectionFixture.context(
            argv: ["/proj/bin/Debug/net8.0/MyApi"],
            executablePath: "/proj/bin/Debug/net8.0/MyApi",
            projectFiles: ["appsettings.json", "MyApi.csproj"],
            ports: [5000]
        )

        #expect(engine.detect(context).type == .aspNet)
    }

    @Test("dotnet exec of an assembly in a web SDK project is ASP.NET Core")
    func dotnetExecOfWebAssembly() {
        let context = DetectionFixture.context(
            argv: ["dotnet", "exec", "/proj/bin/Debug/net8.0/MyApi.dll"],
            executablePath: "/usr/local/share/dotnet/dotnet",
            dependencies: ["microsoft.net.sdk.web"],
            ports: [5000]
        )

        #expect(engine.detect(context).type == .aspNet)
    }

    @Test("a release build output is recognised as well as a debug one")
    func releaseBuildOutput() {
        let context = DetectionFixture.context(
            argv: ["/proj/bin/Release/net9.0/MyApi"],
            executablePath: "/proj/bin/Release/net9.0/MyApi",
            projectFiles: ["appsettings.Production.json"],
            ports: [5001]
        )

        #expect(engine.detect(context).type == .aspNet)
    }

    @Test("a build output binary with no web evidence is generic .NET")
    func consoleAppIsGenericDotNet() {
        let context = DetectionFixture.context(
            argv: ["/proj/bin/Debug/net8.0/Worker"],
            executablePath: "/proj/bin/Debug/net8.0/Worker",
            projectFiles: ["Worker.csproj"],
            ports: [5000]
        )
        let type = engine.detect(context).type

        #expect(type == .dotnet)
        #expect(type != .aspNet)
    }

    @Test("dotnet exec of a loose tool is generic .NET")
    func looseToolIsGenericDotNet() {
        let context = DetectionFixture.context(
            argv: ["dotnet", "exec", "/tmp/sometool.dll"],
            executablePath: "/usr/local/share/dotnet/dotnet",
            ports: [5000]
        )
        let type = engine.detect(context).type

        #expect(type == .dotnet)
        #expect(type != .aspNet)
    }

    @Test("Flask on 5000 is Flask, not ASP.NET")
    func flaskKeepsPortFiveThousand() {
        // The two share a default port and nothing else. Neither may reach its
        // threshold on the other's process.
        let context = DetectionFixture.context(
            command: "flask run --port 5000",
            executablePath: "/proj/.venv/bin/flask",
            dependencies: ["flask"],
            ports: [5000]
        )
        let type = engine.detect(context).type

        #expect(type == .flask)
        #expect(type != .aspNet)
        #expect(type != .dotnet)
    }

    @Test("MSBuild is build infrastructure, not a service")
    func msbuildIsVetoed() {
        let context = DetectionFixture.context(
            argv: ["dotnet", "/usr/local/share/dotnet/sdk/8.0.100/MSBuild.dll", "/nodemode:1"],
            executablePath: "/usr/local/share/dotnet/dotnet",
            ports: [5000]
        )
        let type = engine.detect(context).type

        #expect(type != .dotnet)
        #expect(type != .aspNet)
    }

    @Test("a test host is not a development service")
    func testHostIsVetoed() {
        let context = DetectionFixture.context(
            argv: ["dotnet", "exec", "/proj/bin/Debug/net8.0/testhost.dll", "--port", "5000"],
            executablePath: "/usr/local/share/dotnet/dotnet",
            ports: [5000]
        )

        #expect(engine.detect(context).type != .dotnet)
    }

    @Test("a bundled .NET runtime inside an app belongs to that app")
    func appBundleRuntimeIsVetoed() {
        // Rider ships its own backend. Detection outranks the classifier's bundle
        // rule, so without the veto it would be promoted to a dev service.
        let context = DetectionFixture.context(
            argv: ["/Applications/Rider.app/Contents/plugins/dotnet/dotnet", "exec", "backend.dll"],
            executablePath: "/Applications/Rider.app/Contents/plugins/dotnet/dotnet",
            ports: [5000]
        )

        #expect(engine.detect(context).type != .dotnet)
    }

    @Test("port 5000 alone identifies nothing")
    func airplayReceiverStaysUnknown() {
        // macOS AirPlay Receiver holds 5000 and offers no command evidence.
        let context = DetectionFixture.context(
            argv: ["/usr/libexec/rapportd"],
            executablePath: "/usr/libexec/rapportd",
            ports: [5000]
        )

        #expect(engine.detect(context).type == .unknown)
    }
}
