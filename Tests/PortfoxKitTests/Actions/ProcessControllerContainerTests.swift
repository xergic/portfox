import Darwin
import Testing
@testable import PortfoxKit

/// A container row's `rootProcess` is the forwarder that publishes every
/// container's port on the machine. Signalling it would take all of them down at
/// once, and the row's classification alone cannot stop that, because the Stop
/// button is offered without asking whether the service is user-managed.
@Suite("Signalling a container row")
struct ProcessControllerContainerTests {
    private var containerService: RunningService {
        makeService(
            port: 5432,
            project: nil,
            // The forwarder's own pid. Real, alive and owned by the user, so
            // every check in `safetyCheck` would wave it through.
            pid: getpid(),
            executable: "/Applications/Docker.app/Contents/MacOS/com.docker.backend",
            classification: .infrastructure,
            container: ContainerSnapshot(id: "c0ffee", name: "shop-db-1", image: "postgres:16")
        )
    }

    @Test("Stop refuses without signalling")
    func stopRefuses() async {
        let outcome = await ProcessController().stop(containerService)

        #expect(outcome == ProcessController.containerRefusal)
        #expect(!outcome.didStop)
    }

    @Test("Force Stop refuses without signalling")
    func forceStopRefuses() async {
        let outcome = await ProcessController().forceStop(containerService, tree: ProcessTree(processes: []))

        #expect(outcome == ProcessController.containerRefusal)
        #expect(!outcome.didStop)
    }

    @Test("Restart refuses a container row")
    func relaunchRefuses() {
        guard case .failure(let refusal) = RelaunchCommand.make(for: containerService) else {
            Issue.record("a container row must not produce a relaunch command")
            return
        }

        #expect(refusal == .managedService)
    }
}
