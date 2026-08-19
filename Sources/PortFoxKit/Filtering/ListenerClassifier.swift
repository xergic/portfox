import Foundation

/// Sorts listeners into the four buckets of spec section 16, so the popover can
/// show ten real services instead of ninety raw listeners.
public struct ListenerClassifier: Sendable {
    /// Directories whose contents are user code. An unidentified process working
    /// inside one of these is probably a dev server worth showing.
    private let codeDirectories: [String]

    public init(codeDirectories: [String] = ListenerClassifier.defaultCodeDirectories()) {
        self.codeDirectories = codeDirectories
    }

    public static func defaultCodeDirectories() -> [String] { [] }

    public func classify(process: ProcessSnapshot, detection: DetectionResult, ports: [Int]) -> ServiceClass {
        .systemNoise
    }
}
