import Foundation

/// Pulling the two useful facts out of an image reference.
public enum ContainerImage {
    /// The repository part of an image, lowercased, with the digest, the tag and
    /// the registry host removed. `ghcr.io/acme/api:v2` becomes `acme/api`.
    ///
    /// Dropping the registry host is a correctness requirement, not tidiness.
    /// `containsToken` treats `.` as a boundary, so a full reference of
    /// `redis.example.com/myapp:1` token-matches `redis` and a private registry's
    /// hostname would identify every image it serves.
    public static func repository(_ image: String) -> String {
        let withoutDigest = image.lowercased().split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
        let withoutTag = stripTag(withoutDigest)

        var components = withoutTag.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if components.count > 1, isRegistryHost(components[0]) { components.removeFirst() }
        return components.joined(separator: "/")
    }

    /// The repository split into its words, on both `/` and `-`.
    /// `confluentinc/cp-kafka` becomes `confluentinc`, `cp`, `kafka`.
    public static func repositoryComponents(_ image: String) -> [String] {
        repository(image)
            .split(whereSeparator: { $0 == "/" || $0 == "-" })
            .map(String.init)
    }

    /// The numeric part of the tag, or nil when the tag names no version.
    /// `postgres:16-alpine` gives `16`, `node:latest` and `myapp:main` give nil.
    public static func versionTag(_ image: String) -> String? {
        let lowered = image.lowercased()
        // A digest pins a build, not a version, and says nothing a user can read.
        guard !lowered.contains("@") else { return nil }
        guard let tag = tagComponent(lowered) else { return nil }

        let numeric = tag.split(separator: "-", maxSplits: 1).first.map(String.init) ?? tag
        return VersionResolver.isVersionLike(numeric) ? numeric : nil
    }

    /// A tag is what follows the last colon, but only when no slash follows it.
    /// `localhost:5000/myapp` carries a registry port, not a tag.
    private static func tagComponent(_ reference: String) -> String? {
        guard let colon = reference.lastIndex(of: ":") else { return nil }
        let candidate = String(reference[reference.index(after: colon)...])
        guard !candidate.isEmpty, !candidate.contains("/") else { return nil }
        return candidate
    }

    private static func stripTag(_ reference: String) -> String {
        guard let tag = tagComponent(reference) else { return reference }
        return String(reference.dropLast(tag.count + 1))
    }

    private static func isRegistryHost(_ component: String) -> Bool {
        component == "localhost" || component.contains(".") || component.contains(":")
    }
}
