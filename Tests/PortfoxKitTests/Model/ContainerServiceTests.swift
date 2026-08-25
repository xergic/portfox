import Foundation
import Testing
@testable import PortfoxKit

@Suite("A container row")
struct ContainerServiceTests {
    private func row(
        image: String,
        composeProject: String? = "shop",
        composeService: String? = "db",
        workingDirectory: String? = nil
    ) -> RunningService {
        makeService(
            port: 5432,
            project: nil,
            pid: 900,
            executable: "/Applications/Docker.app/Contents/MacOS/com.docker.backend",
            classification: .infrastructure,
            container: ContainerSnapshot(
                id: "c0ffee",
                name: "shop-db-1",
                image: image,
                composeProject: composeProject,
                composeService: composeService,
                composeWorkingDirectory: workingDirectory
            )
        )
    }

    /// The rule the whole design rests on. `ContainerSnapshot` reaches
    /// `RunningService`'s synthesised `Equatable`, which is what decides whether
    /// the dashboard repaints. A moved image has to be visible, and an unchanged
    /// container has to compare equal or an idle machine redraws once a second.
    @Test("a changed image compares unequal")
    func changedImageComparesUnequal() {
        #expect(row(image: "postgres:16") != row(image: "postgres:17"))
    }

    @Test("an unchanged container compares equal")
    func unchangedContainerComparesEqual() {
        #expect(row(image: "postgres:16") == row(image: "postgres:16"))
    }

    @Test("the subtitle names the compose project and service, not the runtime")
    func subtitleNamesCompose() {
        #expect(row(image: "postgres:16").subtitle == "shop · db")
    }

    @Test("a container started outside compose falls back to its own name")
    func subtitleFallsBackToName() {
        let service = row(image: "postgres:16", composeProject: nil, composeService: nil)

        #expect(service.subtitle == "shop-db-1")
    }

    /// The forwarder's working directory is inside the Docker or OrbStack bundle.
    /// Revealing it would open a folder the user has never seen.
    @Test("there is nothing to reveal without a compose directory")
    func nothingToReveal() {
        #expect(row(image: "postgres:16").revealDirectory == nil)
    }
}
