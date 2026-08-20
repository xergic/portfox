import Foundation
import Testing
@testable import PortfoxKit

/// The manifest readers exist to feed detection, not to fill in project headings.
/// These go through the real `ProjectResolver` rather than a fixture, because the
/// two ecosystems below are undetectable without it and a fixture that hands the
/// dependency over directly would prove nothing.
@Suite("manifests unlock detection")
struct ManifestToDetectionTests {
    @Test("a Gemfile is what makes Rails detectable at all")
    func gemfileUnlocksRails() throws {
        // `rails server` hands the socket to Puma, which rewrites its own argv to
        // `puma 6.4.2 (tcp://0.0.0.0:3000) [app]`. Nothing on the command line
        // says Rails, so the Gemfile is the only remaining evidence.
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("source \"https://rubygems.org\"\ngem \"rails\", \"~> 7.1\"\ngem \"puma\"\n", at: "Gemfile")

        let project = try #require(ProjectResolver().resolve(serviceDirectory: tree.root))
        #expect(project.hasDependency("rails"))

        let context = DetectionContext(
            process: ProcessSnapshot(
                pid: 4242,
                parentPID: 1,
                uid: 501,
                executablePath: "/Users/me/.rbenv/versions/3.3.0/bin/ruby",
                arguments: ["puma", "6.4.2", "(tcp://0.0.0.0:3000)", "[shop]"]
            ),
            project: project,
            ports: [3000]
        )

        #expect(DetectionEngine().detect(context).type == .rails)
    }

    @Test("a csproj web SDK attribute is what makes ASP.NET detectable at all")
    func csprojUnlocksASPNET() throws {
        // `dotnet run` execs an apphost named after the project, so the only thing
        // distinguishing a web app from a console app is the project file's Sdk.
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(
            "<Project Sdk=\"Microsoft.NET.Sdk.Web\">\n  <PropertyGroup></PropertyGroup>\n</Project>\n",
            at: "MyApi.csproj"
        )

        let project = try #require(ProjectResolver().resolve(serviceDirectory: tree.root))
        #expect(project.hasDependency("microsoft.net.sdk.web"))

        let context = DetectionContext(
            process: ProcessSnapshot(
                pid: 4243,
                parentPID: 1,
                uid: 501,
                executablePath: "\(tree.root.path)/bin/Debug/net8.0/MyApi",
                arguments: ["\(tree.root.path)/bin/Debug/net8.0/MyApi"]
            ),
            project: project,
            ports: [5000]
        )

        #expect(DetectionEngine().detect(context).type == .aspNet)
    }

    @Test("a pom.xml is what makes a Spring Boot fat jar detectable at all")
    func pomUnlocksSpringBootFatJar() throws {
        // `java -jar target/app-0.0.1-SNAPSHOT.jar` carries no Spring evidence.
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(
            """
            <project>
              <artifactId>demo</artifactId>
              <dependencies>
                <dependency>
                  <groupId>org.springframework.boot</groupId>
                  <artifactId>spring-boot-starter-web</artifactId>
                </dependency>
              </dependencies>
            </project>
            """,
            at: "pom.xml"
        )

        let project = try #require(ProjectResolver().resolve(serviceDirectory: tree.root))
        #expect(project.hasDependency("spring-boot-starter-web"))

        let context = DetectionContext(
            process: ProcessSnapshot(
                pid: 4244,
                parentPID: 1,
                uid: 501,
                executablePath: "/opt/homebrew/opt/openjdk/bin/java",
                arguments: ["java", "-jar", "\(tree.root.path)/target/demo-0.0.1-SNAPSHOT.jar"]
            ),
            project: project,
            ports: [8080]
        )

        #expect(DetectionEngine().detect(context).type == .springBoot)
    }
}
