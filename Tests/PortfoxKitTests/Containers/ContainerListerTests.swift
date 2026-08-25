import Testing
@testable import PortfoxKit

@Suite("docker ps output parsing")
struct ContainerListerTests {
    /// `\u{1F}` is the field separator the format string asks for. Written as an
    /// escape rather than pasted, so a fixture cannot lose it to an editor.
    private func line(_ fields: String...) -> String {
        fields.joined(separator: "\u{1F}")
    }

    @Test("parses a compose stack")
    func parsesComposeStack() {
        let output = [
            line("abc123", "shop-db-1", "postgres:16", "shop", "db", "/Users/ondra/Work/shop",
                 "0.0.0.0:5432->5432/tcp, :::5432->5432/tcp"),
            line("def456", "shop-cache-1", "redis:7-alpine", "shop", "cache", "/Users/ondra/Work/shop",
                 "0.0.0.0:6379->6379/tcp")
        ].joined(separator: "\n")

        let containers = ContainerLister.parse(output)

        #expect(containers.count == 2)
        #expect(containers[0].id == "abc123")
        #expect(containers[0].name == "shop-db-1")
        #expect(containers[0].image == "postgres:16")
        #expect(containers[0].composeProject == "shop")
        #expect(containers[0].composeService == "db")
        #expect(containers[0].composeWorkingDirectory == "/Users/ondra/Work/shop")
        #expect(containers[0].publishedPorts.map(\.hostPort) == [5432])
        #expect(containers[1].image == "redis:7-alpine")
    }

    @Test("a container without compose labels reports nil, not empty strings")
    func missingLabelsAreNil() throws {
        let output = line("abc123", "wistful_hopper", "postgres:16", "", "", "", "0.0.0.0:5432->5432/tcp")

        let container = try #require(ContainerLister.parse(output).first)

        #expect(container.composeProject == nil)
        #expect(container.composeService == nil)
        #expect(container.composeWorkingDirectory == nil)
        #expect(container.displayLabel == "wistful_hopper")
    }

    @Test("empty output yields nothing")
    func emptyOutput() {
        #expect(ContainerLister.parse("").isEmpty)
    }

    @Test("a malformed line is skipped and its neighbours survive")
    func malformedLineIsSkipped() {
        let output = [
            line("abc123", "one", "postgres:16", "", "", "", "0.0.0.0:5432->5432/tcp"),
            "this line has no separators at all",
            line("def456", "two", "redis:7", "", "", "", "0.0.0.0:6379->6379/tcp")
        ].joined(separator: "\n")

        #expect(ContainerLister.parse(output).map(\.name) == ["one", "two"])
    }

    // MARK: - Published ports

    @Test("a dual-stack publish is one mapping")
    func dualStackIsOneMapping() {
        let ports = ContainerLister.parsePorts("0.0.0.0:5432->5432/tcp, :::5432->5432/tcp")

        #expect(ports.count == 1)
        #expect(ports[0].hostPort == 5432)
        #expect(ports[0].containerPort == 5432)
    }

    @Test("reads the bracketed IPv6 form older docker emits")
    func bracketedIPv6() {
        let ports = ContainerLister.parsePorts("[::]:8080->80/tcp")

        #expect(ports.map(\.hostPort) == [8080])
        #expect(ports[0].hostAddress == "::")
        #expect(ports[0].containerPort == 80)
    }

    @Test("reads a loopback publish")
    func loopbackPublish() {
        let ports = ContainerLister.parsePorts("127.0.0.1:6379->6379/tcp")

        #expect(ports.map(\.hostPort) == [6379])
        #expect(ports[0].hostAddress == "127.0.0.1")
    }

    /// Exposed is not published. Nothing holds a host socket, so there is nothing
    /// for a listener to be attributed to.
    @Test("an exposed but unpublished port claims nothing")
    func exposedIsNotPublished() {
        #expect(ContainerLister.parsePorts("5432/tcp").isEmpty)
    }

    @Test("a range expands")
    func rangeExpands() {
        let ports = ContainerLister.parsePorts("0.0.0.0:5000-5002->5000-5002/tcp")

        #expect(ports.map(\.hostPort) == [5000, 5001, 5002])
        #expect(ports.map(\.containerPort) == [5000, 5001, 5002])
    }

    /// Otherwise `-p 1-65535` turns one container into sixty-five thousand rows.
    @Test("an over-wide range is refused outright")
    func overWideRangeRefused() {
        #expect(ContainerLister.parsePorts("0.0.0.0:1-65535->1-65535/tcp").isEmpty)
    }

    /// lsof reports only TCP, so a UDP publish must never claim a socket.
    @Test("a UDP publish is dropped")
    func udpDropped() {
        #expect(ContainerLister.parsePorts("0.0.0.0:53->53/udp").isEmpty)
    }

    @Test("a mixed cell keeps only the TCP half")
    func mixedCell() {
        let ports = ContainerLister.parsePorts("0.0.0.0:53->53/udp, 0.0.0.0:8080->80/tcp")

        #expect(ports.map(\.hostPort) == [8080])
    }

    @Test("an empty cell yields nothing")
    func emptyCell() {
        #expect(ContainerLister.parsePorts("").isEmpty)
    }
}
