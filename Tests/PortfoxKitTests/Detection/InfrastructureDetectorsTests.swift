import Testing
@testable import PortfoxKit

@Suite("infrastructure detectors")
struct InfrastructureDetectorsTests {
    let engine = DetectionEngine(detectors: DetectorCatalog.python + DetectorCatalog.infrastructure)

    @Test("Homebrew postgres is detected from its exe path")
    func homebrewPostgres() {
        let context = DetectionFixture.context(
            argv: ["/opt/homebrew/opt/postgresql@17/bin/postgres", "-D", "/opt/homebrew/var/postgresql@17"],
            executablePath: "/opt/homebrew/opt/postgresql@17/bin/postgres",
            ports: [5432]
        )

        #expect(engine.detect(context).type == .postgres)
    }

    @Test("DBngin postgres on a non-default port is still detected from its exe name")
    func dbnginPostgres() {
        let enginePath = "/Users/Shared/DBngin/postgresql/17.0/bin/postgres"
        let context = DetectionFixture.context(
            argv: [
                enginePath, "-D",
                "/Users/Ondra/Library/Application Support/com.tinyapp.DBngin/Engines/postgresql/3C934D2E", "-p", "5435"
            ],
            executablePath: enginePath,
            ports: [5435]
        )

        #expect(engine.detect(context).type == .postgres)
    }

    @Test("a process on port 5432 with an unrelated executable is not reported as postgres")
    func unrelatedExeOnPostgresPort() {
        let context = DetectionFixture.context(
            argv: ["node", "server.js"],
            executablePath: "/usr/local/bin/node",
            ports: [5432]
        )

        #expect(engine.detect(context).type != .postgres)
    }

    @Test("mysqld is detected from its exe name")
    func mysql() {
        let context = DetectionFixture.context(
            argv: ["mysqld", "--port", "3306"],
            executablePath: "/opt/homebrew/opt/mysql/bin/mysqld",
            ports: [3306]
        )

        #expect(engine.detect(context).type == .mysql)
    }

    @Test("mongod is detected from its exe name")
    func mongodb() {
        let context = DetectionFixture.context(
            argv: ["mongod", "--dbpath", "/data/db", "--port", "27017"],
            executablePath: "/opt/homebrew/opt/mongodb-community/bin/mongod",
            ports: [27017]
        )

        #expect(engine.detect(context).type == .mongodb)
    }

    @Test("DBngin redis with a trailing-space argv title is still detected")
    func dbnginRedis() {
        let enginePath = "/Users/Shared/DBngin/redis/7.0.0/bin/redis-server"
        let context = DetectionFixture.context(
            argv: [enginePath, "*:6379   "],
            executablePath: enginePath,
            ports: [6379]
        )

        #expect(engine.detect(context).type == .redis)
    }

    @Test("meilisearch is detected from its exe name")
    func meilisearch() {
        let context = DetectionFixture.context(
            argv: ["meilisearch", "--http-addr", "0.0.0.0:7700"],
            executablePath: "/opt/homebrew/bin/meilisearch",
            ports: [7700]
        )

        #expect(engine.detect(context).type == .meilisearch)
    }

    @Test("elasticsearch running under java is detected from its bootstrap class")
    func elasticsearch() {
        let context = DetectionFixture.context(
            argv: [
                "/opt/homebrew/opt/openjdk/bin/java", "-Xms1g", "-Xmx1g",
                "-cp", "/opt/homebrew/opt/elasticsearch/lib/*", "org.elasticsearch.bootstrap.Elasticsearch"
            ],
            executablePath: "/opt/homebrew/opt/openjdk/bin/java",
            ports: [9200]
        )

        #expect(engine.detect(context).type == .elasticsearch)
    }

    @Test("a plain java process is not reported as elasticsearch")
    func plainJavaIsNotElasticsearch() {
        let context = DetectionFixture.context(
            argv: ["java", "-jar", "app.jar"],
            executablePath: "/opt/homebrew/opt/openjdk/bin/java",
            ports: [9200]
        )

        #expect(engine.detect(context).type != .elasticsearch)
    }

    @Test("minio is detected from its exe name")
    func minio() {
        let context = DetectionFixture.context(
            argv: ["minio", "server", "/data", "--console-address", ":9001"],
            executablePath: "/opt/homebrew/bin/minio",
            ports: [9000, 9001]
        )

        #expect(engine.detect(context).type == .minio)
    }

    @Test("mailpit is detected from its exe name")
    func mailpit() {
        let context = DetectionFixture.context(
            argv: ["mailpit"],
            executablePath: "/opt/homebrew/bin/mailpit",
            ports: [8025, 1025]
        )

        #expect(engine.detect(context).type == .mailpit)
    }

    @Test("a postgres worker with a rewritten argv title neither crashes nor is misidentified")
    func postgresWorkerArgvTitle() {
        let context = DetectionFixture.context(argv: ["postgres: walwriter"])

        #expect(engine.detect(context).type == .unknown)
    }

    @Test("rabbitmq is detected from the beam.smp command line, not its exe name")
    func rabbitmq() {
        let context = DetectionFixture.context(
            argv: [
                "/opt/homebrew/opt/rabbitmq/erts-14.2/bin/beam.smp", "-W", "w", "-A", "128",
                "-pa", "/opt/homebrew/opt/rabbitmq/plugins", "-noshell", "-s", "rabbitmq-server"
            ],
            executablePath: "/opt/homebrew/opt/rabbitmq/erts-14.2/bin/beam.smp",
            ports: [5672, 15672]
        )

        #expect(engine.detect(context).type == .rabbitmq)
    }
}
