import Foundation

/// One scored signal, kept whether it matched or not so the diagnostics view can
/// render the full checklist described in spec section 15.
public struct EvidenceItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String { description }

    public let description: String
    public let points: Int
    public let matched: Bool

    public init(description: String, points: Int, matched: Bool) {
        self.description = description
        self.points = points
        self.matched = matched
    }
}

public struct DetectionResult: Hashable, Codable, Sendable {
    public let type: ServiceType
    public let score: Int
    /// `score` divided by the total weight available, capped at 1.0.
    public let confidence: Double
    public let evidence: [EvidenceItem]

    public init(type: ServiceType, score: Int, confidence: Double, evidence: [EvidenceItem]) {
        self.type = type
        self.score = score
        self.confidence = confidence
        self.evidence = evidence
    }

    public static func unknown() -> DetectionResult {
        DetectionResult(type: .unknown, score: 0, confidence: 0, evidence: [])
    }

    public var matchedEvidence: [EvidenceItem] { evidence.filter(\.matched) }
}
