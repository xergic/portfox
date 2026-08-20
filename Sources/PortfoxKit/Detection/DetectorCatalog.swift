import Foundation

/// The complete detector table. Every entry is declarative, so supporting a new
/// framework costs one row here and one asset in the catalogue.
public enum DetectorCatalog {
    public static let all: [any ServiceDetector] =
        nodeEcosystem + python + jvm + dotNet + ruby + php + compiled + infrastructure

    /// Databases and daemons. Kept as one property, and as a concatenation rather
    /// than a rename, because two test suites build engines from this name.
    public static let infrastructure: [any ServiceDetector] = databases + daemons

    /// Threshold shared by detectors whose strongest signal is a bin path. Set
    /// above any single weak signal so a lone port or dependency never wins.
    public static let standardThreshold = 90
}
