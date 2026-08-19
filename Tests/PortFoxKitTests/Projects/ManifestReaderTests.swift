import Foundation
import Testing
@testable import PortFoxKit

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

    @Test("returns empty when a directory has no manifests")
    func readReturnsEmptyWhenNothingFound() {
        let tree = TempTree()
        defer { tree.cleanUp() }

        #expect(ManifestReader.read(in: tree.root) == .empty)
    }
}
