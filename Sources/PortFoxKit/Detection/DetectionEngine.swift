import Foundation

/// Runs every detector and picks a winner.
public struct DetectionEngine: Sendable {
    private let detectors: [any ServiceDetector]

    public init(detectors: [any ServiceDetector] = DetectorCatalog.all) {
        self.detectors = detectors
    }

    /// Highest score wins. Ties break toward the more specific service type, so a
    /// Next.js server is never reported as generic Node. Remaining ties break
    /// toward higher confidence.
    public func detect(_ context: DetectionContext) -> DetectionResult {
        let results = detectors.compactMap { $0.detect(context) }
        guard !results.isEmpty else { return .unknown() }

        return results.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.type.specificity != rhs.type.specificity {
                return lhs.type.specificity < rhs.type.specificity
            }
            return lhs.confidence < rhs.confidence
        } ?? .unknown()
    }

    /// Every result above threshold, best first. Used by the diagnostics view.
    public func allMatches(_ context: DetectionContext) -> [DetectionResult] {
        detectors.compactMap { $0.detect(context) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.type.specificity > rhs.type.specificity
            }
    }
}
