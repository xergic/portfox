import Foundation

private extension DetectionContext {
    static let rabbitPorts = [5672, 15672, 25672]
}

public extension DetectorCatalog {
    /// Local daemons, queues, proxies and developer tooling. None of these needs
    /// project context: the executable name alone identifies them.
    static let daemons: [any ServiceDetector] = [
        RuleBasedDetector(
            type: .minio,
            threshold: standardThreshold,
            signals: [
                .containerImage(["minio"]),
                .executableNamed("minio", 100),
                .defaultPorts([9000, 9001])
            ]
        ),
        RuleBasedDetector(
            type: .mailpit,
            threshold: standardThreshold,
            signals: [
                .containerImage(["mailpit"]),
                .executableNamed("mailpit", 100),
                .defaultPorts([8025, 1025])
            ]
        ),
        RuleBasedDetector(
            type: .rabbitmq,
            threshold: standardThreshold,
            signals: [
                .containerImage(["rabbitmq"]),
                // The real executable is the Erlang VM (beam.smp), shared with every
                // other Erlang app, so identity comes from the command line instead.
                .executableNamed("rabbitmq-server", 95),
                .commandContains("rabbitmq-server", 90),
                .custom("an Erlang VM bound to a RabbitMQ port", 90, group: "command") { ctx in
                    // A live node runs as beam.smp, which is shared with every
                    // other Erlang application, so the port has to carry it.
                    ctx.executableName == "beam.smp" && ctx.ports.contains { DetectionContext.rabbitPorts.contains($0) }
                },
                .defaultPorts([5672, 15672])
            ]
        ),
        RuleBasedDetector(
            type: .mailhog,
            threshold: standardThreshold,
            signals: [
                .containerImage(["mailhog"]),
                .executableNameContains("mailhog", 100),
                .defaultPorts([8025, 1025])
            ]
        ),
        RuleBasedDetector(
            type: .kafka,
            threshold: standardThreshold,
            signals: [
                .containerImage(["kafka"]),
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
                .containerImage(["nats"]),
                // `nats` is the CLI. The server is always `nats-server`.
                .executableNamed("nats-server", 100),
                .defaultPorts([4222, 8222])
            ]
        ),
        RuleBasedDetector(
            type: .temporal,
            threshold: standardThreshold,
            signals: [
                .containerImage(["temporal", "temporalio"]),
                .executableNamed("temporal", 100),
                .commandContains("server start-dev", 88),
                .defaultPorts([8233, 7233])
            ]
        ),
        RuleBasedDetector(
            type: .nginx,
            threshold: standardThreshold,
            signals: [
                .containerImage(["nginx"]),
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
                .containerImage(["caddy"]),
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
                .containerImage(["grafana"]),
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
                .containerImage(["prometheus"]),
                .executableNamed("prometheus", 100),
                .defaultPort(9090)
            ]
        ),
        RuleBasedDetector(
            type: .ollama,
            threshold: standardThreshold,
            signals: [
                .containerImage(["ollama"]),
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
                // The forwarder itself, for a published port no container claimed:
                // Docker Desktop's own API port, an OrbStack machine port, or any
                // machine whose daemon could not be asked.
                .custom("a container port forwarder", 100, group: "command") { ctx in
                    ContainerRuntime.forwarderNames.contains(ctx.executableName)
                        || ContainerRuntime.forwarderPathFragments.contains(where: ctx.executablePath.contains)
                },
                // The fallback for a container whose image names nothing known.
                // Weighted at exactly `standardThreshold`, and that number is the
                // invariant: any lower and every container reads as Docker again,
                // any higher and it outranks a real image row. An unidentified
                // container must still reach the threshold, because `.unknown`
                // would send it to `ListenerClassifier`, which sees the forwarder
                // sitting inside Docker.app and buries the row as system noise.
                .custom("a published container port whose image names nothing known", standardThreshold,
                        group: "command") { $0.containerImage != nil }
            ]
        )
    ]
}
