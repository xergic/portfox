import Foundation
import Testing
@testable import PortfoxKit

/// Whole-catalogue invariants. Each of these caught, or would have caught, a hole
/// that no individual detector test can see: Mailpit shipped without an icon for
/// three releases because nothing checked the set as a whole.
@Suite("catalogue guards")
struct CatalogueGuardTests {
    @Test("every service type has a detector")
    func everyTypeHasADetector() {
        let covered = Set(DetectorCatalog.all.map(\.type))
        let missing = ServiceType.allCases.filter { $0 != .unknown && !covered.contains($0) }

        #expect(missing.isEmpty, "no detector for \(missing.map(\.rawValue).sorted())")
    }

    @Test("every detector can reach its own threshold")
    func everyDetectorCanFire() {
        // A typo in a weight, or a threshold raised without adjusting the signals
        // under it, produces a row that cannot match anything. It stays invisible
        // until a user reports the service as unrecognised.
        for detector in DetectorCatalog.all.compactMap({ $0 as? RuleBasedDetector }) {
            #expect(
                detector.maximumScore >= detector.threshold,
                "\(detector.type.rawValue) can score at most \(detector.maximumScore), needs \(detector.threshold)"
            )
        }
    }

    @Test("every detector owns a command-group signal")
    func everyDetectorIsGated() {
        // The requiredGroup gate only bites when the detector actually declares a
        // signal in that group. A row built entirely from dependencies and ports
        // silently opts out, and project evidence alone identifies the service.
        for detector in DetectorCatalog.all.compactMap({ $0 as? RuleBasedDetector }) {
            guard let group = detector.requiredGroup else { continue }
            let gated = detector.signals.contains { !$0.isVeto && $0.group == group }

            #expect(gated, "\(detector.type.rawValue) has no \(group) signal, so its gate never applies")
        }
    }

    @Test("every service type has a bundled icon or a declared reason not to")
    func everyTypeHasAnIconDecision() throws {
        // Reads Tools/fetch-icons.py rather than mirroring its allowlist, so the
        // two cannot drift apart.
        let root = Self.repositoryRoot()
        let script = try String(
            contentsOf: root.appending(path: "Tools/fetch-icons.py"),
            encoding: .utf8
        )
        let assets = root.appending(path: "App/Portfox/Resources/Assets.xcassets/Services")

        for type in ServiceType.allCases {
            let imageset = assets.appending(path: "\(type.iconAssetName).imageset")
            let hasAsset = FileManager.default.fileExists(atPath: imageset.path)
            let isDeclared = script.contains("\"\(type.rawValue)\":")

            #expect(hasAsset || isDeclared, "\(type.rawValue) has no icon and no NO_BRAND_ICON entry")
        }
    }

    @Test("ports listed as a default are never the only evidence")
    func portsAloneIdentifyNothing() {
        // The single most common way to get a confident wrong answer. Anything a
        // detector claims as a default port must still resolve to unknown when
        // that is all there is.
        let engine = DetectionEngine()
        let claimed = Set(ServiceType.allCases.flatMap(\.defaultPorts))

        for port in claimed.sorted() {
            let context = DetectionFixture.context(
                command: "/opt/anonymous/bin/server --quiet",
                executablePath: "/opt/anonymous/bin/server",
                ports: [port]
            )

            #expect(engine.detect(context).type == .unknown, "port \(port) alone identified a service")
        }
    }

    @Test("an unrelated image identifies nothing but Docker")
    func imageAloneIdentifiesOnlyItsOwnService() {
        // The mirror of the port guard, for the other kind of thin evidence. An
        // image that names none of the catalogue must fall to `.docker`, never to
        // whichever detector happened to carry a matching default port.
        let engine = DetectionEngine()

        for image in ["alpine:3.20", "busybox", "myorg/shop-api:v3", "ghcr.io/acme/worker:latest"] {
            let context = DetectionFixture.containerContext(image: image)

            #expect(engine.detect(context).type == .docker, "\(image) identified something")
        }
    }

    /// Walks up from this file to the directory holding Package.swift.
    private static func repositoryRoot() -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appending(path: "Package.swift").path) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
