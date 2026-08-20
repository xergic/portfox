import Foundation

private extension DetectionContext {
    /// JVM processes that listen on a port but are never the user's service:
    /// build daemons, test forks, debug transports and editor language servers.
    ///
    /// Gated on `isJVM` so a Postgres or Node listener costs one string compare
    /// rather than twenty. Vetoes are evaluated for every process against every
    /// detector, so an ungated scan here is paid by the whole catalogue.
    ///
    /// This is a denylist over an unbounded set, so it will need entries added.
    /// What actually carries the weight is `ListenerClassifier`'s ephemeral-port
    /// rule, which hides anything bound only above 49152 before detection is even
    /// consulted. This list is for the tooling that picks a low fixed port.
    var isJVMTooling: Bool {
        guard isJVM else { return false }
        if Self.toolingMarkers.contains(where: command.contains) { return true }
        // A debug or management transport is the only listener these open.
        return command.contains("-agentlib:jdwp") || command.contains("com.sun.management.jmxremote")
    }

    static let toolingMarkers = [
        // Gradle
        "org.gradle.launcher.daemon", "org.gradle.process.internal.worker", "gradleworkermain",
        // Maven, and its test forks
        "org.apache.maven.surefire.booter", "org.codehaus.plexus.classworlds.launcher",
        // Kotlin, Scala, sbt
        "kotlin-daemon", "org.jetbrains.kotlin.daemon", "scala.tools.nsc",
        "xsbt.boot.boot", "sbt.forkmain", "bloop",
        // JetBrains
        "com.intellij", "org.jetbrains.jps", "idea_rt", "nailgun",
        // Eclipse and the VS Code Java extensions
        "org.eclipse.equinox.launcher", "org.eclipse.jdt.ls", "com.microsoft.java.debug",
        // Test runners
        "junitplatform.consolelauncher", "org.testng.remote",
        // Bazel
        "com.google.devtools.build"
    ]

    static let springArtefactPaths = ["/target/", "/build/libs/", "/build/classes/"]
}

private extension Signal {
    /// Declared once, applied to every JVM row. A veto only disqualifies the
    /// detector that declares it, so the repetition at the call sites is
    /// required even though the value is not.
    static let jvmTooling = Signal.veto("a JVM build daemon, test fork or language server") { $0.isJVMTooling }
}

public extension DetectorCatalog {
    /// JVM services. Every one of them runs as the same `java` executable, so
    /// identity has to come from the classpath.
    ///
    /// Classpath entries are version-suffixed jar names (`spring-boot-3.2.0.jar`),
    /// which `containsToken` deliberately refuses to match because `-` and digits
    /// are word characters. These rows therefore fall back to raw `contains`,
    /// always behind `isJVM` so a path that merely mentions a framework cannot
    /// claim one.
    ///
    /// Every row repeats the `isJVMTooling` veto. A veto only disqualifies the
    /// detector that declares it, so without the repetition a Surefire test fork
    /// whose classpath happens to carry `spring-boot-test` would be reported as a
    /// running application.
    static let jvm: [any ServiceDetector] = [
        RuleBasedDetector(
            type: .springBoot,
            threshold: standardThreshold,
            signals: [
                .custom("a JVM whose classpath contains a spring-boot jar", 100, group: "command") { ctx in
                    ctx.isJVM && ctx.command.contains("spring-boot")
                },
                .custom("a JVM whose classpath contains the Spring framework", 85, group: "command") { ctx in
                    ctx.isJVM && ctx.command.containsToken("springframework")
                },
                .custom("launched by the Spring Boot Maven plugin", 92, group: "command") { ctx in
                    ctx.isJVM && ctx.anyCommandContains("spring-boot:run")
                },
                // A fat jar's argv is only `java -jar target/app-0.0.1-SNAPSHOT.jar`.
                // The build artefact path plus the project's own manifest is the
                // only evidence that survives packaging.
                .custom("java -jar of a build artefact in a Spring Boot project", 90, group: "command") { ctx in
                    guard ctx.isJVM, let project = ctx.project else { return false }
                    guard DetectionContext.springArtefactPaths.contains(where: ctx.command.contains) else {
                        return false
                    }
                    return project.hasDependency("spring-boot-starter-web")
                        || project.hasDependency("spring-boot-starter-webflux")
                        || project.hasDependency("org.springframework.boot")
                },
                .anyDependency(
                    ["spring-boot-starter-web", "spring-boot-starter-webflux", "org.springframework.boot"],
                    60
                ),
                .defaultPort(8080),
                .veto("a JVM build daemon, test fork or language server") { $0.isJVMTooling },
                .veto("Elasticsearch is a JVM service with its own detector") { $0.command.contains("elasticsearch") },
                .veto("Kafka is a JVM service with its own detector") { $0.command.contains("kafka") }
            ]
        ),
        RuleBasedDetector(
            type: .quarkus,
            threshold: standardThreshold,
            signals: [
                .custom("a JVM whose classpath contains Quarkus", 100, group: "command") { ctx in
                    ctx.isJVM && (ctx.command.containsToken("io.quarkus") || ctx.command.containsToken("quarkus"))
                },
                .custom("launched by the Quarkus dev goal", 92, group: "command") { ctx in
                    ctx.isJVM && ctx.anyCommandContains("quarkus:dev")
                },
                .anyDependency(["quarkus-resteasy-reactive", "quarkus-rest", "io.quarkus"], 60),
                .defaultPort(8080),
                .veto("a JVM build daemon, test fork or language server") { $0.isJVMTooling }
            ]
        ),
        RuleBasedDetector(
            type: .micronaut,
            threshold: standardThreshold,
            signals: [
                .custom("a JVM whose classpath contains Micronaut", 100, group: "command") { ctx in
                    ctx.isJVM && ctx.command.containsToken("micronaut")
                },
                .anyDependency(["micronaut-http-server-netty", "io.micronaut"], 60),
                .defaultPort(8080),
                .veto("a JVM build daemon, test fork or language server") { $0.isJVMTooling }
            ]
        ),
        RuleBasedDetector(
            type: .tomcat,
            threshold: standardThreshold,
            signals: [
                // `-Dcatalina.base=` lowercases to `-dcatalina.base=`, and the
                // leading `d` defeats containsToken's boundary check.
                .custom("the Catalina bootstrap class or a catalina.base flag", 100, group: "command") { ctx in
                    ctx.isJVM && ctx.command.contains("catalina")
                },
                .defaultPorts([8080, 8443]),
                .veto("a JVM build daemon, test fork or language server") { $0.isJVMTooling },
                .veto("Spring Boot embeds Tomcat and owns the service") { ctx in
                    ctx.command.contains("spring-boot") || ctx.command.containsToken("springframework")
                }
            ]
        ),
        RuleBasedDetector(
            type: .ktor,
            threshold: standardThreshold,
            signals: [
                .custom("a JVM whose classpath contains Ktor", 100, group: "command") { ctx in
                    ctx.isJVM && ctx.command.containsToken("io.ktor")
                },
                .dependency("io.ktor", 60),
                .defaultPort(8080),
                .veto("a JVM build daemon, test fork or language server") { $0.isJVMTooling }
            ]
        ),
        RuleBasedDetector(
            type: .java,
            threshold: 20,
            signals: [
                .executableNamed("java", 30),
                .executableNamed("javaw", 30),
                .defaultPorts([8080, 8000]),
                .veto("a JVM build daemon, test fork or language server") { $0.isJVMTooling },
                // Detection outranks the classifier's bundle rule, so without this
                // an IDE's own bundled JRE would be promoted to a dev service.
                .vetoAppBundle()
            ]
        )
    ]
}
