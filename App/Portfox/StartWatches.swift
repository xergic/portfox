import Foundation
import Observation
import PortfoxKit

/// Things the user is waiting on to come up, such as the dev server an agent
/// is about to start. Each fires one banner and disarms.
///
/// In memory only. A wait outlives neither its timeout nor the app, and a
/// banner for something the user asked about yesterday would be a surprise.
@MainActor
@Observable
final class StartWatches {
    struct Wait {
        let deadline: Date
        /// What the give-up banner calls it, captured when armed.
        let label: String
    }

    static let timeoutMinutes = 15

    private(set) var waits: [StartTarget: Wait] = [:]

    var isArmed: Bool { !waits.isEmpty }

    func isArmed(_ target: StartTarget) -> Bool { waits[target] != nil }

    func toggle(_ target: StartTarget, label: String) {
        if waits[target] != nil {
            waits[target] = nil
        } else {
            waits[target] = Wait(deadline: .now.addingTimeInterval(TimeInterval(Self.timeoutMinutes * 60)), label: label)
        }
    }

    /// The targets that came up, each with the service that answered it,
    /// disarmed as they are returned.
    func fire(in scan: ScanResult, appeared: [RunningService]) -> [RunningService] {
        let fired = waits.keys.compactMap { target in
            scan.service(answering: target, appeared: appeared).map { (target, $0) }
        }
        for (target, _) in fired { waits[target] = nil }
        return fired.map(\.1)
    }

    /// Labels of the waits whose time ran out, disarmed as they are returned.
    /// Wall-clock time on purpose: a Mac asleep past the deadline has waited.
    func expire() -> [String] {
        let now = Date.now
        let expired = waits.filter { $0.value.deadline <= now }
        for target in expired.keys { waits[target] = nil }
        return expired.values.map(\.label)
    }
}
