import Foundation

public extension DetectorCatalog {
    /// Local daemons, queues, proxies and developer tooling. None of these needs
    /// project context: the executable name alone identifies them.
    static let daemons: [any ServiceDetector] = [
        RuleBasedDetector(
            type: .minio,
            threshold: standardThreshold,
            signals: [
                .executableNamed("minio", 100),
                .defaultPorts([9000, 9001])
            ]
        ),
        RuleBasedDetector(
            type: .mailpit,
            threshold: standardThreshold,
            signals: [
                .executableNamed("mailpit", 100),
                .defaultPorts([8025, 1025])
            ]
        ),
        RuleBasedDetector(
            type: .rabbitmq,
            threshold: standardThreshold,
            signals: [
                // The real executable is the Erlang VM (beam.smp), shared with every
                // other Erlang app, so identity comes from the command line instead.
                .executableNamed("rabbitmq-server", 95),
                .commandContains("rabbitmq-server", 90),
                .custom("an Erlang VM bound to a RabbitMQ port", 90, group: "command") { ctx in
                    // A live node runs as beam.smp, which is shared with every
                    // other Erlang application, so the port has to carry it.
                    ctx.executableName == "beam.smp" && ctx.ports.contains { [5672, 15672, 25672].contains($0) }
                },
                .defaultPorts([5672, 15672])
            ]
        )
    ]
}
