import Foundation

public protocol ServiceDetector: Sendable {
    var type: ServiceType { get }
    func detect(_ context: DetectionContext) -> DetectionResult?
}

/// The detector every entry in `DetectorCatalog` uses. Scoring, grouping and
/// evidence collection live here once, so a detector is a table row.
public struct RuleBasedDetector: ServiceDetector {
    public let type: ServiceType
    /// Minimum score to claim the service. Set it above the weight of any single
    /// weak signal so a lone port or dependency match never identifies a service.
    public let threshold: Int
    public let signals: [Signal]
    /// Signal group that must produce at least one match, whatever the score.
    ///
    /// Without this, project evidence alone identifies a service: `adb` running
    /// inside an Expo project scored 130 from `app.json` plus the `expo`
    /// dependency and was reported as Expo. A service is what a process is
    /// running, not what sits in its working directory.
    public let requiredGroup: String?

    public init(type: ServiceType, threshold: Int, signals: [Signal], requiredGroup: String? = "command") {
        self.type = type
        self.threshold = threshold
        self.signals = signals
        self.requiredGroup = requiredGroup
    }

    public func detect(_ context: DetectionContext) -> DetectionResult? {
        var evidence: [EvidenceItem] = []
        var bestPerGroup: [String: Int] = [:]
        var ungroupedScore = 0

        for signal in signals {
            let matched = signal.matches(context)

            if signal.isVeto {
                if matched { return nil }
                continue
            }

            evidence.append(EvidenceItem(description: signal.description, points: signal.weight, matched: matched))
            guard matched else { continue }

            if let group = signal.group {
                bestPerGroup[group] = max(bestPerGroup[group] ?? Int.min, signal.weight)
            } else {
                ungroupedScore += signal.weight
            }
        }

        if let requiredGroup, signals.contains(where: { $0.group == requiredGroup && !$0.isVeto }) {
            guard bestPerGroup[requiredGroup] != nil else { return nil }
        }

        let score = ungroupedScore + bestPerGroup.values.reduce(0, +)
        guard score >= threshold else { return nil }

        let denominator = maximumScore
        let confidence = denominator > 0 ? min(1.0, Double(score) / Double(denominator)) : 0
        return DetectionResult(type: type, score: score, confidence: confidence, evidence: evidence)
    }

    /// Highest score this detector can produce, counting each group once.
    var maximumScore: Int {
        var groupMaxima: [String: Int] = [:]
        var total = 0
        for signal in signals where !signal.isVeto && signal.weight > 0 {
            if let group = signal.group {
                groupMaxima[group] = max(groupMaxima[group] ?? 0, signal.weight)
            } else {
                total += signal.weight
            }
        }
        return total + groupMaxima.values.reduce(0, +)
    }
}
