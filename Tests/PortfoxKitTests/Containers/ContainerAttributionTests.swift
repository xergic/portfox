import Testing
@testable import PortfoxKit

@Suite("Attributing sockets to containers")
struct ContainerAttributionTests {
    private func container(_ id: String, image: String, hostPorts: [Int]) -> ContainerSnapshot {
        ContainerSnapshot(
            id: id,
            name: id,
            image: image,
            publishedPorts: hostPorts.map {
                PublishedPort(hostAddress: "0.0.0.0", hostPort: $0, containerPort: $0, transport: "tcp")
            }
        )
    }

    private func socket(_ port: Int, family: ListeningSocket.AddressFamily = .ipv4) -> ListeningSocket {
        ListeningSocket(pid: 900, port: port, host: family == .ipv4 ? "0.0.0.0" : "::", family: family)
    }

    @Test("one forwarder's sockets split across three containers")
    func splitsAcrossContainers() {
        let containers = [
            container("db", image: "postgres:16", hostPorts: [5432]),
            container("cache", image: "redis:7", hostPorts: [6379]),
            container("web", image: "nginx:alpine", hostPorts: [8080])
        ]

        let result = ContainerAttribution.attribute(
            sockets: [socket(8080), socket(5432), socket(6379)],
            to: containers
        )

        #expect(result.owned.count == 3)
        #expect(result.owned.map(\.container.id) == ["db", "cache", "web"])
        #expect(result.residual.isEmpty)
    }

    @Test("IPv4 and IPv6 on one host port land on the same container")
    func dualStackLandsOnce() {
        let result = ContainerAttribution.attribute(
            sockets: [socket(5432), socket(5432, family: .ipv6)],
            to: [container("db", image: "postgres:16", hostPorts: [5432])]
        )

        #expect(result.owned.count == 1)
        #expect(result.owned[0].sockets.count == 2)
        #expect(result.residual.isEmpty)
    }

    /// Docker Desktop's own API port belongs to no container. It has to survive
    /// as a plain Docker row rather than disappear from the list.
    @Test("a socket no container published becomes residual")
    func unattributedSocketIsResidual() {
        let result = ContainerAttribution.attribute(
            sockets: [socket(5432), socket(2375)],
            to: [container("db", image: "postgres:16", hostPorts: [5432])]
        )

        #expect(result.owned.map(\.container.id) == ["db"])
        #expect(result.residual.map(\.port) == [2375])
    }

    /// The path a machine takes when the daemon could not be asked. Everything
    /// falls to residual, which is today's single Docker row.
    @Test("no containers leaves everything residual")
    func noContainersLeavesResidual() {
        let result = ContainerAttribution.attribute(sockets: [socket(5432), socket(6379)], to: [])

        #expect(result.owned.isEmpty)
        #expect(result.residual.map(\.port) == [5432, 6379])
    }

    @Test("a container with no live socket is not listed")
    func idleContainerIsNotListed() {
        let result = ContainerAttribution.attribute(
            sockets: [socket(5432)],
            to: [
                container("db", image: "postgres:16", hostPorts: [5432]),
                container("cache", image: "redis:7", hostPorts: [6379])
            ]
        )

        #expect(result.owned.map(\.container.id) == ["db"])
    }
}
