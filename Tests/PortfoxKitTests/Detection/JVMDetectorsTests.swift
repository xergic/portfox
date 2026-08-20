import Testing
@testable import PortfoxKit

@Suite("JVM detectors")
struct JVMDetectorsTests {
    private let engine = DetectionEngine(
        detectors: DetectorCatalog.jvm + DetectorCatalog.infrastructure + DetectorCatalog.nodeEcosystem
    )

    @Test("a Maven fat jar with a spring-boot dependency on the classpath is Spring Boot")
    func mavenForkedRunIsSpringBoot() {
        let context = DetectionFixture.context(
            command: "java -cp /proj/target/classes:/Users/me/.m2/repository/org/springframework/boot/" +
                "spring-boot/3.2.0/spring-boot-3.2.0.jar com.example.App",
            executablePath: "/usr/bin/java",
            ports: [8080]
        )

        #expect(engine.detect(context).type == .springBoot)
    }

    @Test("a Gradle cache classpath entry under org.springframework.boot is Spring Boot")
    func gradleClasspathIsSpringBoot() {
        let context = DetectionFixture.context(
            command: "java -cp /home/me/.gradle/caches/modules-2/files-2.1/org.springframework.boot/" +
                "spring-boot/3.2.0/a1b2c3d4e5f6/spring-boot-3.2.0.jar:/proj/build/classes/java/main " +
                "com.example.DemoApplication",
            executablePath: "/usr/bin/java",
            ports: [8080]
        )

        #expect(engine.detect(context).type == .springBoot)
    }

    @Test("java -jar of a build artefact in a project that depends on spring-boot-starter-web is Spring Boot")
    func fatJarWithSpringBootDependencyIsSpringBoot() {
        let context = DetectionFixture.context(
            command: "java -jar /proj/target/demo-0.0.1-SNAPSHOT.jar",
            executablePath: "/usr/bin/java",
            dependencies: ["spring-boot-starter-web"],
            ports: [8080]
        )

        #expect(engine.detect(context).type == .springBoot)
    }

    @Test("the identical fat jar with no dependency evidence is generic Java, not Spring Boot")
    func fatJarWithoutDependencyIsJava() {
        let context = DetectionFixture.context(
            command: "java -jar /proj/target/demo-0.0.1-SNAPSHOT.jar",
            executablePath: "/usr/bin/java",
            ports: [8080]
        )

        let type = engine.detect(context).type
        #expect(type == .java)
        #expect(type != .springBoot)
    }

    @Test("Elasticsearch running under java is Elasticsearch, not generic Java or Spring Boot")
    func elasticsearchUnderJavaIsElasticsearch() {
        let context = DetectionFixture.context(
            command: "java -Xms1g -Xmx1g -cp /opt/homebrew/opt/elasticsearch/lib/* " +
                "org.elasticsearch.bootstrap.Elasticsearch",
            executablePath: "/usr/bin/java",
            ports: [9200]
        )

        let type = engine.detect(context).type
        #expect(type == .elasticsearch)
        #expect(type != .java)
        #expect(type != .springBoot)
    }

    @Test("Kafka's bootstrap class on the classpath is Kafka")
    func kafkaBootstrapClassIsKafka() {
        let context = DetectionFixture.context(
            command: "java -cp /opt/kafka/libs/* kafka.Kafka config/server.properties",
            executablePath: "/usr/bin/java",
            ports: [9092]
        )

        #expect(engine.detect(context).type == .kafka)
    }

    @Test("the Gradle daemon is neither generic Java nor Spring Boot")
    func gradleDaemonIsNotJavaOrSpringBoot() {
        let context = DetectionFixture.context(
            command: "java -cp /opt/homebrew/gradle/lib/gradle-launcher.jar " +
                "org.gradle.launcher.daemon.bootstrap.GradleDaemon",
            executablePath: "/usr/bin/java",
            ports: [8080]
        )

        let type = engine.detect(context).type
        #expect(type != .java)
        #expect(type != .springBoot)
    }

    @Test("a Surefire test fork whose classpath carries spring-boot-test is not reported as Spring Boot")
    func surefireForkWithSpringBootTestJarIsNotSpringBoot() {
        // isJVMTooling is the veto that has to catch this: the classpath alone
        // contains the raw substring "spring-boot", which is otherwise a 100
        // point signal, so only the Surefire marker keeps the fork from being
        // reported as a running application.
        let context = DetectionFixture.context(
            command: "java -cp /proj/target/test-classes:/proj/target/classes:" +
                "/Users/me/.m2/repository/org/springframework/boot/spring-boot-test/3.2.0/" +
                "spring-boot-test-3.2.0.jar org.apache.maven.surefire.booter.SurefireBooter",
            executablePath: "/usr/bin/java",
            ports: [8080]
        )

        #expect(engine.detect(context).type != .springBoot)
    }

    @Test("a JDWP debug transport is not reported as generic Java")
    func jdwpTransportIsNotJava() {
        let context = DetectionFixture.context(
            command: "java -agentlib:jdwp=transport=dt_socket,server=y,address=5005 -jar app.jar",
            executablePath: "/usr/bin/java",
            ports: [5005]
        )

        #expect(engine.detect(context).type != .java)
    }

    @Test("Tomcat's Catalina bootstrap class is Tomcat")
    func catalinaBootstrapIsTomcat() {
        let context = DetectionFixture.context(
            command: "java -Dcatalina.base=/opt/tomcat -cp /opt/tomcat/bin/bootstrap.jar " +
                "org.apache.catalina.startup.Bootstrap start",
            executablePath: "/usr/bin/java",
            ports: [8080]
        )

        #expect(engine.detect(context).type == .tomcat)
    }

    @Test("Spring Boot's embedded Tomcat is reported as Spring Boot, not Tomcat")
    func springBootEmbeddedTomcatIsSpringBoot() {
        let context = DetectionFixture.context(
            command: "java -cp /proj/target/classes:/m2/org/springframework/boot/spring-boot/3.2.0/" +
                "spring-boot-3.2.0.jar:/m2/org/apache/catalina/embed/catalina-embed-core-10.1.0.jar " +
                "org.springframework.boot.loader.launch.JarLauncher",
            executablePath: "/usr/bin/java",
            ports: [8080]
        )

        let type = engine.detect(context).type
        #expect(type == .springBoot)
        #expect(type != .tomcat)
    }

    @Test("Quarkus happy path")
    func quarkusHappyPath() {
        let context = DetectionFixture.context(
            command: "java -cp /proj/target/quarkus-app/quarkus-run.jar io.quarkus.runner.GeneratedMain",
            executablePath: "/usr/bin/java",
            ports: [8080]
        )

        #expect(engine.detect(context).type == .quarkus)
    }

    @Test("Micronaut happy path")
    func micronautHappyPath() {
        let context = DetectionFixture.context(
            command: "java -cp /proj/build/libs/app.jar io.micronaut.runtime.Micronaut",
            executablePath: "/usr/bin/java",
            ports: [8080]
        )

        #expect(engine.detect(context).type == .micronaut)
    }

    @Test("Ktor happy path")
    func ktorHappyPath() {
        let context = DetectionFixture.context(
            command: "java -cp /proj/build/libs/app.jar io.ktor.server.netty.EngineMain",
            executablePath: "/usr/bin/java",
            ports: [8080]
        )

        #expect(engine.detect(context).type == .ktor)
    }

    @Test("a JVM inside an application bundle is not reported as generic Java")
    func jvmInsideAppBundleIsNotJava() {
        let context = DetectionFixture.context(
            command: "java -jar /Applications/IntelliJ IDEA.app/Contents/plugins/java/lib/rt.jar",
            executablePath: "/Applications/IntelliJ IDEA.app/Contents/jbr/Contents/Home/bin/java",
            ports: [8080]
        )

        #expect(engine.detect(context).type != .java)
    }

    @Test("a node server whose project name mentions spring-boot is reported as Node, never Java evidence")
    func nodeServerInSpringBootNamedDirectoryIsNode() {
        let context = DetectionFixture.context(
            command: "node /Users/me/Code/spring-boot-demo/server.js",
            executablePath: "/usr/local/bin/node",
            ports: [8080]
        )

        #expect(engine.detect(context).type == .node)
    }
}
