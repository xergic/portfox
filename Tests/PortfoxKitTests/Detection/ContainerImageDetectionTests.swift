import Testing
@testable import PortfoxKit

@Suite("Detection from a container image")
struct ContainerImageDetectionTests {
    private let engine = DetectionEngine()

    @Test("an image names the service it runs", arguments: [
        ("postgres:16", ServiceType.postgres),
        ("redis:7-alpine", ServiceType.redis),
        ("mysql:8", ServiceType.mysql),
        ("mongo:7", ServiceType.mongodb),
        ("ghcr.io/acme/nginx:1.27", ServiceType.nginx),
        ("confluentinc/cp-kafka:7.6.0", ServiceType.kafka),
        ("prom/prometheus:v2.51", ServiceType.prometheus),
        ("temporalio/auto-setup:1.22", ServiceType.temporal)
    ])
    func imageIdentifiesService(image: String, expected: ServiceType) {
        #expect(engine.detect(DetectionFixture.containerContext(image: image)).type == expected)
    }

    @Test("a vendored build still names the service")
    func vendoredBuild() {
        #expect(engine.detect(DetectionFixture.containerContext(image: "bitnami/postgresql:16")).type == .postgres)
    }

    /// The whole point of blanking the derived strings. The forwarder's real
    /// executable is on `ctx.process`, and if a detector could still read it the
    /// `.docker` row would match at full weight and beat the image.
    @Test("the forwarder's own executable does not win over the image")
    func imageBeatsForwarder() {
        let context = DetectionFixture.containerContext(
            image: "postgres:16",
            executablePath: "/Applications/Docker.app/Contents/MacOS/docker-proxy"
        )

        #expect(context.process.executableName == "docker-proxy")
        #expect(engine.detect(context).type == .postgres)
    }

    /// Not `.unknown`. An unidentified container has to keep a row, and `.unknown`
    /// would send it to `ListenerClassifier`, which sees the forwarder inside
    /// Docker.app and buries it as system noise.
    @Test("an unrecognised image still reads as Docker")
    func unrecognisedImageIsDocker() {
        #expect(engine.detect(DetectionFixture.containerContext(image: "alpine:3.20")).type == .docker)
    }

    @Test("a port is not evidence when the image names nothing")
    func portAloneIsNotEvidence() {
        let context = DetectionFixture.containerContext(image: "alpine:3.20", ports: [5432])

        #expect(engine.detect(context).type == .docker)
    }

    /// The word-boundary guard, in image form.
    @Test("a name that merely starts the same is refused")
    func partialNameRefused() {
        #expect(engine.detect(DetectionFixture.containerContext(image: "huggingface/mongoku")).type == .docker)
    }

    /// A private registry's hostname must not identify every image it serves.
    @Test("a registry hostname is not evidence")
    func registryHostnameIsNotEvidence() {
        let context = DetectionFixture.containerContext(image: "redis.example.com/myapp:1")

        #expect(engine.detect(context).type == .docker)
    }
}
