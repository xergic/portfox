import Foundation

extension Duration {
    /// Seconds as a `TimeInterval`, for the Foundation and Dispatch APIs that
    /// still take one.
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

/// Resumes a continuation exactly once, whichever caller gets there first.
///
/// Every spawn in the kit races a termination handler against a timeout, and both
/// must be free to fire. Resuming a `CheckedContinuation` twice is a crash, so the
/// race is settled here rather than in each caller.
final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let continuation: CheckedContinuation<Value, Never>
    private let lock = NSLock()
    private var finished = false

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Value) {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()
        guard !alreadyFinished else { return }
        continuation.resume(returning: value)
    }
}
