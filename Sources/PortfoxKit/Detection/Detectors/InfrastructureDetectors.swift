import Foundation

public extension DetectorCatalog {
    /// Databases and local daemons. These need no project context. The same binary
    /// often ships from several installers (Homebrew, DBngin, Postgres.app, ...) at
    /// different paths, so every signal matches on the executable's last path
    /// component rather than the full path.
    static let infrastructure: [any ServiceDetector] = [
        RuleBasedDetector(
            type: .postgres,
            threshold: standardThreshold,
            signals: [
                .executableNamed("postgres", 100),
                .defaultPort(5432)
            ]
        ),
        RuleBasedDetector(
            type: .mysql,
            threshold: standardThreshold,
            signals: [
                .executableNamed("mysqld", 100),
                .defaultPort(3306)
            ]
        ),
        RuleBasedDetector(
            type: .mongodb,
            threshold: standardThreshold,
            signals: [
                .executableNamed("mongod", 100),
                .defaultPort(27017)
            ]
        ),
        RuleBasedDetector(
            type: .redis,
            threshold: standardThreshold,
            signals: [
                .executableNamed("redis-server", 100),
                .defaultPort(6379)
            ]
        ),
        RuleBasedDetector(
            type: .meilisearch,
            threshold: standardThreshold,
            signals: [
                .executableNamed("meilisearch", 100),
                .defaultPort(7700)
            ]
        ),
        RuleBasedDetector(
            type: .elasticsearch,
            threshold: standardThreshold,
            signals: [
                // Runs under the generic "java" executable, so identity has to come
                // from the bootstrap class on the command line, never the exe name.
                .commandContains("org.elasticsearch.bootstrap.elasticsearch", 90),
                .commandContains("/elasticsearch", 90),
                .defaultPort(9200)
            ]
        ),
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
