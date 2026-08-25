import Testing
@testable import PortfoxKit

@Suite("Container image references")
struct ContainerImageTests {
    @Test("drops the tag", arguments: [
        ("postgres:16", "postgres"),
        ("redis:7-alpine", "redis"),
        ("alpine", "alpine")
    ])
    func dropsTag(image: String, expected: String) {
        #expect(ContainerImage.repository(image) == expected)
    }

    @Test("drops the digest")
    func dropsDigest() {
        #expect(ContainerImage.repository("postgres@sha256:abc123") == "postgres")
    }

    @Test("drops the registry host", arguments: [
        ("ghcr.io/acme/api:v2", "acme/api"),
        ("docker.io/library/redis:7", "library/redis"),
        ("localhost:5000/myapp:v1", "myapp")
    ])
    func dropsRegistry(image: String, expected: String) {
        #expect(ContainerImage.repository(image) == expected)
    }

    /// The registry host has to go or `containsToken` matches through it: `.` is
    /// not a word character, so `redis.example.com/myapp` would read as Redis and
    /// one private registry would identify every image it serves.
    @Test("a registry hostname never identifies the image")
    func registryHostnameIsNotEvidence() {
        let repository = ContainerImage.repository("redis.example.com/myapp:1")
        #expect(repository == "myapp")
        #expect(!repository.contains("redis"))
    }

    @Test("keeps a namespace that is not a registry")
    func keepsNamespace() {
        #expect(ContainerImage.repository("bitnami/postgresql:16") == "bitnami/postgresql")
    }

    @Test("reads a version tag", arguments: [
        ("postgres:16", "16"),
        ("redis:7-alpine", "7"),
        ("nginx:1.27", "1.27")
    ])
    func readsVersion(image: String, expected: String) {
        #expect(ContainerImage.versionTag(image) == expected)
    }

    @Test("refuses a tag that names no version", arguments: [
        "node:latest", "myapp:main", "alpine", "ghcr.io/acme/api:v2",
        "postgres@sha256:abc123", "localhost:5000/myapp"
    ])
    func refusesNonVersion(image: String) {
        #expect(ContainerImage.versionTag(image) == nil)
    }
}
