import Foundation
import Testing
@testable import PortfoxKit

@Suite("manifest parsing")
struct ManifestReaderTests {
    @Test("reads name and unions dependencies from all three sections")
    func packageJSONDependencies() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(
            """
            {
                "name": "my-app",
                "dependencies": { "react": "^18.0.0" },
                "devDependencies": { "TypeScript": "^5.0.0" },
                "peerDependencies": { "vue": "^3.0.0" },
                "scripts": { "dev": "vite" }
            }
            """,
            at: "package.json"
        )

        let manifest = ManifestReader.packageJSON(in: tree.root)

        #expect(manifest?.name == "my-app")
        #expect(manifest?.dependencies == ["react", "typescript", "vue"])
        #expect(manifest?.scripts == ["dev": "vite"])
        #expect(manifest?.declaresWorkspaces == false)
    }

    @Test("detects workspaces declared as an array")
    func workspacesArrayForm() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "name": "root", "workspaces": ["apps/*", "packages/*"] }"#, at: "package.json")

        #expect(ManifestReader.packageJSON(in: tree.root)?.declaresWorkspaces == true)
    }

    @Test("detects workspaces declared as an object")
    func workspacesObjectForm() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "name": "root", "workspaces": { "packages": ["apps/*"] } }"#, at: "package.json")

        #expect(ManifestReader.packageJSON(in: tree.root)?.declaresWorkspaces == true)
    }

    @Test("reads name and dependency names from pyproject.toml under [project]")
    func pyprojectProjectSection() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(
            """
            [project]
            name = "my-service"
            dependencies = ["fastapi>=0.100", "uvicorn[standard]==0.30", "pydantic"]
            """,
            at: "pyproject.toml"
        )

        let manifest = ManifestReader.pyproject(in: tree.root)

        #expect(manifest?.name == "my-service")
        #expect(manifest?.dependencies == ["fastapi", "uvicorn", "pydantic"])
    }

    @Test("reads name and dependency names from a poetry pyproject.toml")
    func pyprojectPoetrySection() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(
            """
            [tool.poetry]
            name = "poetry-service"

            [tool.poetry.dependencies]
            python = "^3.11"
            Django = "^5.0"
            """,
            at: "pyproject.toml"
        )

        let manifest = ManifestReader.pyproject(in: tree.root)

        #expect(manifest?.name == "poetry-service")
        #expect(manifest?.dependencies == ["python", "django"])
    }

    @Test("strips comments, editable installs, extras and version specifiers")
    func requirementsTxtStripping() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(
            """
            # top level comment
            Flask==2.3.0
            requests>=2.0,<3.0
            -e ./local-package
            uvicorn[standard]~=0.30
            numpy  # inline comment
            """,
            at: "requirements.txt"
        )

        let manifest = ManifestReader.requirementsTxt(in: tree.root)

        #expect(manifest?.dependencies == ["flask", "requests", "uvicorn", "numpy"])
    }

    @Test("reads expo config nested under the expo key")
    func expoNestedKey() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "expo": { "name": "MyExpoApp", "icon": "./assets/icon.png" } }"#, at: "app.json")

        let manifest = ManifestReader.expoConfig(in: tree.root)

        #expect(manifest?.name == "MyExpoApp")
        #expect(manifest?.declaredIconPath == "./assets/icon.png")
        #expect(manifest?.dependencies == ["expo"])
    }

    @Test("reads expo config fields at the top level")
    func expoTopLevel() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "name": "MyExpoApp", "icon": "./icon.png" }"#, at: "app.json")

        let manifest = ManifestReader.expoConfig(in: tree.root)

        #expect(manifest?.name == "MyExpoApp")
        #expect(manifest?.declaredIconPath == "./icon.png")
    }

    @Test("reads Maven artifact and group identifiers")
    func pomXMLDependencies() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(
            """
            <project>
              <groupId>com.example</groupId>
              <artifactId>web-service</artifactId>
              <dependencies><dependency><artifactId>spring-boot-starter-web</artifactId></dependency></dependencies>
            </project>
            """,
            at: "pom.xml"
        )

        let manifest = ManifestReader.pomXML(in: tree.root)

        #expect(manifest?.name == "web-service")
        #expect(manifest?.dependencies.contains("spring-boot-starter-web") == true)
        #expect(manifest?.dependencies.contains("com.example") == true)
    }

    @Test("reads Gradle coordinates and plugins")
    func gradleBuildDependencies() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(
            """
            plugins { id("org.springframework.boot") }
            dependencies { implementation("org.springframework.boot:spring-boot-starter-web:3.2.0") }
            """,
            at: "build.gradle.kts"
        )
        tree.write("rootProject.name = \"Spring Service\"", at: "settings.gradle.kts")

        let manifest = ManifestReader.gradleBuild(in: tree.root)

        #expect(manifest?.name == "Spring Service")
        #expect(manifest?.dependencies.contains("spring-boot-starter-web") == true)
        #expect(manifest?.dependencies.contains("org.springframework.boot:spring-boot-starter-web") == true)
        #expect(manifest?.dependencies.contains("org.springframework.boot") == true)
    }

    @Test("reads Rails dependencies from a Gemfile")
    func gemfileDependencies() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("gem \"rails\", \"~> 7.1\"", at: "Gemfile")

        #expect(ManifestReader.gemfile(in: tree.root)?.dependencies.contains("rails") == true)
    }

    @Test("reads Composer packages and vendor names")
    func composerJSONDependencies() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "name": "acme/site", "require": { "laravel/framework": "^11.0" } }"#, at: "composer.json")

        let manifest = ManifestReader.composerJSON(in: tree.root)

        #expect(manifest?.name == "acme/site")
        #expect(manifest?.dependencies.contains("laravel/framework") == true)
        #expect(manifest?.dependencies.contains("laravel") == true)
    }

    @Test("reads .NET SDK and package references case-insensitively")
    func csprojDependencies() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(
            """
            <Project Sdk="Microsoft.NET.Sdk.Web">
              <ItemGroup><PackageReference Include="Microsoft.AspNetCore.OpenApi" /></ItemGroup>
            </Project>
            """,
            at: "MyApi.csproj"
        )

        let manifest = ManifestReader.csproj(in: tree.root)

        #expect(manifest?.dependencies.contains("microsoft.net.sdk.web") == true)
        #expect(manifest?.dependencies.contains("microsoft.aspnetcore.openapi") == true)
    }

    @Test("lowercases dependencies from newly supported manifests")
    func mixedCaseDependenciesAreLowercased() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("gem \"Rails\"", at: "Gemfile")

        let snapshot = ProjectResolver().resolve(serviceDirectory: tree.root)

        #expect(snapshot?.hasDependency("rails") == true)
    }

    @Test("reads Cargo package metadata and dependency keys")
    func cargoTOMLDependencies() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("""
        [package]
        name = "rust-service"
        version = "0.1.0"

        [dependencies]
        Axum = "0.7"
        """, at: "Cargo.toml")

        let manifest = ManifestReader.cargoTOML(in: tree.root)

        #expect(manifest?.name == "rust-service")
        #expect(manifest?.version == "0.1.0")
        #expect(manifest?.dependencies.contains("axum") == true)
    }

    @Test("reads the Go module name")
    func goModName() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("module github.com/acme/go-service\n\ngo 1.23", at: "go.mod")

        #expect(ManifestReader.goMod(in: tree.root)?.name == "go-service")
    }

    @Test("reads Deno metadata and import keys")
    func denoJSONMetadata() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "name": "deno-service", "version": "1.0.0", "imports": { "@std/path": "jsr:@std/path" } }"#, at: "deno.json")

        let manifest = ManifestReader.denoJSON(in: tree.root)

        #expect(manifest?.name == "deno-service")
        #expect(manifest?.version == "1.0.0")
        #expect(manifest?.dependencies.contains("@std/path") == true)
    }

    @Test("returns empty when a directory has no manifests")
    func readReturnsEmptyWhenNothingFound() {
        let tree = TempTree()
        defer { tree.cleanUp() }

        #expect(ManifestReader.read(in: tree.root) == .empty)
    }
}
