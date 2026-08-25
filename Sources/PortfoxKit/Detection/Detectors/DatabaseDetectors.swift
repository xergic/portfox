import Foundation

public extension DetectorCatalog {
    /// Databases. The same binary often ships from several installers (Homebrew,
    /// DBngin, Postgres.app, ...) at different paths, so every signal matches on
    /// the executable's last path component rather than the full path.
    static let databases: [any ServiceDetector] = [
        RuleBasedDetector(
            type: .postgres,
            threshold: standardThreshold,
            signals: [
                .containerImage(["postgres", "postgresql"]),
                .executableNamed("postgres", 100),
                .defaultPort(5432)
            ]
        ),
        RuleBasedDetector(
            type: .mysql,
            threshold: standardThreshold,
            signals: [
                .containerImage(["mysql", "mariadb", "percona"]),
                .executableNamed("mysqld", 100),
                .defaultPort(3306)
            ]
        ),
        RuleBasedDetector(
            type: .mongodb,
            threshold: standardThreshold,
            signals: [
                .containerImage(["mongo", "mongodb"]),
                .executableNamed("mongod", 100),
                .defaultPort(27017)
            ]
        ),
        RuleBasedDetector(
            type: .redis,
            threshold: standardThreshold,
            signals: [
                .containerImage(["redis"]),
                .executableNamed("redis-server", 100),
                .defaultPort(6379)
            ]
        ),
        RuleBasedDetector(
            type: .meilisearch,
            threshold: standardThreshold,
            signals: [
                .containerImage(["meilisearch"]),
                .executableNamed("meilisearch", 100),
                .defaultPort(7700)
            ]
        ),
        RuleBasedDetector(
            type: .elasticsearch,
            threshold: standardThreshold,
            signals: [
                .containerImage(["elasticsearch"]),
                // Runs under the generic "java" executable, so identity has to come
                // from the bootstrap class on the command line, never the exe name.
                .commandContains("org.elasticsearch.bootstrap.elasticsearch", 90),
                .commandContains("/elasticsearch", 90),
                .defaultPort(9200)
            ]
        ),
        RuleBasedDetector(
            type: .memcached,
            threshold: standardThreshold,
            signals: [
                .containerImage(["memcached"]),
                .executableNamed("memcached", 100),
                .defaultPort(11211)
            ]
        ),
        RuleBasedDetector(
            type: .valkey,
            threshold: standardThreshold,
            signals: [
                .containerImage(["valkey"]),
                // Shares 6379 with Redis, which it forked from, so the port only
                // ever corroborates and the executable name has to decide.
                .executableNamed("valkey-server", 100),
                .defaultPort(6379)
            ]
        ),
        RuleBasedDetector(
            type: .clickhouse,
            threshold: standardThreshold,
            signals: [
                .containerImage(["clickhouse"]),
                .executableNamed("clickhouse-server", 100),
                .executableNamed("clickhouse", 90),
                .defaultPorts([8123, 9000])
            ]
        ),
        RuleBasedDetector(
            type: .typesense,
            threshold: standardThreshold,
            signals: [
                .containerImage(["typesense"]),
                .executableNameContains("typesense-server", 100),
                .defaultPort(8108)
            ]
        ),
        RuleBasedDetector(
            type: .qdrant,
            threshold: standardThreshold,
            signals: [
                .containerImage(["qdrant"]),
                .executableNamed("qdrant", 100),
                .defaultPorts([6333, 6334])
            ]
        )
    ]
}
