import Foundation
import Observation

/// "Freed ~850 MB" after a stop. Stops close together add up, so a Stop All
/// followed by one more Stop reads as one cleanup, and the figure clears itself.
@MainActor
@Observable
final class FreedMemory {
    static let visibleFor = Duration.seconds(6)

    private(set) var bytes: UInt64 = 0
    @ObservationIgnored private var hide: Task<Void, Never>?

    func add(_ freed: UInt64) {
        guard freed > 0 else { return }
        bytes += freed
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            self?.bytes = 0
        }
    }
}
