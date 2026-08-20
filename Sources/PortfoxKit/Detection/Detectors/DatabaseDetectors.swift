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
        )
    ]
}
