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
        ),
        RuleBasedDetector(
            type: .mailhog,
            threshold: standardThreshold,
            signals: [
                .executableNameContains("mailhog", 100),
                .defaultPorts([8025, 1025])
            ]
        ),
        RuleBasedDetector(
            type: .kafka,
            threshold: standardThreshold,
            signals: [
                // Runs under `java`, like Elasticsearch, and `bin/kafka-server-start.sh`
                // only execs it. Identity is the bootstrap class on the command line.
                .commandContains("kafka.kafka", 100),
                .custom("a JVM whose classpath contains Kafka", 88, group: "command") { ctx in
                    ctx.isJVM && ctx.command.containsToken("kafka")
                },
                .defaultPorts([9092, 9094]),
                .veto("Kafka Connect and the schema registry are separate services") { ctx in
                    ctx.command.contains("connectdistributed") || ctx.command.contains("schemaregistry")
                }
            ]
        ),
        RuleBasedDetector(
            type: .nats,
            threshold: standardThreshold,
            signals: [
                // `nats` is the CLI. The server is always `nats-server`.
                .executableNamed("nats-server", 100),
                .defaultPorts([4222, 8222])
            ]
        ),
        RuleBasedDetector(
            type: .temporal,
            threshold: standardThreshold,
            signals: [
                .executableNamed("temporal", 100),
                .commandContains("server start-dev", 88),
                .defaultPorts([8233, 7233])
            ]
        ),
        RuleBasedDetector(
            type: .nginx,
            threshold: standardThreshold,
            signals: [
                // nginx rewrites its argv to `nginx: master process ...`, which is
                // harmless because executableName comes from proc_pidpath.
                .executableNamed("nginx", 100),
                .commandContains("nginx", 90),
                .defaultPorts([80, 8080])
            ]
        ),
        RuleBasedDetector(
            type: .caddy,
            threshold: standardThreshold,
            signals: [
                .executableNamed("caddy", 100),
                .commandContains("caddy run", 88),
                .defaultPorts([80, 443, 2019])
            ]
        ),
        RuleBasedDetector(
            type: .ngrok,
            threshold: standardThreshold,
            signals: [
                .executableNamed("ngrok", 100),
                .defaultPort(4040)
            ]
        ),
        RuleBasedDetector(
            type: .grafana,
            threshold: standardThreshold,
            signals: [
                // Modern builds run `grafana server`; older ones ship a separate
                // `grafana-server` binary. Both are in the field.
                .executableNamed("grafana", 100),
                .executableNamed("grafana-server", 100),
                .commandContains("grafana", 88),
                .defaultPort(3000)
            ]
        ),
        RuleBasedDetector(
            type: .prometheus,
            threshold: standardThreshold,
            signals: [
                .executableNamed("prometheus", 100),
                .defaultPort(9090)
            ]
        ),
        RuleBasedDetector(
            type: .ollama,
            threshold: standardThreshold,
            signals: [
                .executableNamed("ollama", 100),
                .defaultPort(11434)
            ]
        ),
        RuleBasedDetector(
            type: .pocketbase,
            threshold: standardThreshold,
            signals: [
                .executableNamed("pocketbase", 100),
                .defaultPort(8090)
            ]
        ),
        RuleBasedDetector(
            type: .prismaStudio,
            threshold: standardThreshold,
            signals: [
                // A Node process, not a binary of its own, so the argv carries it.
                .binPath("prisma", 100),
                .commandContains("prisma studio", 92),
                .defaultPort(5555)
            ]
        ),
        RuleBasedDetector(
            type: .docker,
            threshold: standardThreshold,
            signals: [
                // High recall, no precision about *what* is listening. Portfox
                // never sees the container's own process, so Postgres in a
                // container reads as "Docker" and an eight-container compose
                // stack becomes eight identical rows. The row still beats the
                // alternative, which is eight unexplained "Local Process" entries,
                // and `.infrastructure` puts them all in the standalone bucket
                // that the "Hide infrastructure and daemons" preference switches off.
                .executableNamed("com.docker.backend", 100),
                .executableNamed("docker-proxy", 100),
                .executableNamed("vpnkit", 95),
                .custom("an OrbStack, Colima or Lima port forwarder", 95, group: "command") { ctx in
                    ["orbstack", "/colima/", "limactl"].contains(where: ctx.executablePath.contains)
                }
            ]
        )
    ]
}
