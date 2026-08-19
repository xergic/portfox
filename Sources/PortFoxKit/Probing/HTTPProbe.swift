import Foundation

/// The outcome of probing a local HTTP service.
public struct HTTPProbeResult: Hashable, Sendable {
    public let statusCode: Int
    public let title: String?
    public let server: String?
    /// The `Location` header on a redirect, which is the whole story of a 3xx.
    public let location: String?
    public let latency: Duration
}

public enum HTTPProbeError: Error, Equatable, Sendable {
    /// The URL's host is not `localhost`, `127.0.0.1` or `::1`. PortFox only
    /// inspects services running on the same machine, never remote hosts.
    case notLoopback
    /// The URL's scheme is neither `http` nor `https`.
    case notHTTP
    case timedOut
    case transport(String)
}

extension HTTPProbeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notLoopback:
            return "PortFox only inspects local services. Use a loopback URL such as http://localhost or http://127.0.0.1."
        case .notHTTP:
            return "The URL scheme must be http or https."
        case .timedOut:
            return "The request timed out. The service may be slow to respond or not accepting connections on this port."
        case .transport(let message):
            return "The request failed: \(message)"
        }
    }
}

/// Fetches status, title and `Server` header from a local HTTP service.
///
/// This is the only networking PortFox does. Every request stays on loopback: the
/// target URL is checked before connecting, and no redirect is ever followed, so a
/// dev server cannot walk the probe off the machine or trap it in a loop.
public struct HTTPProbe: Sendable {
    private static let maxBodyBytes = 64 * 1_024

    private let timeout: Duration

    public init(timeout: Duration = .seconds(2)) {
        self.timeout = timeout
    }

    public func probe(_ url: URL) async throws -> HTTPProbeResult {
        try Self.validate(url)

        let session = Self.makeSession(timeout: timeout)
        // Cancel rather than finish. The body read stops at 64 KB with a `break`,
        // which leaves the task alive and the connection draining the rest.
        defer { session.invalidateAndCancel() }

        let clock = ContinuousClock()
        let start = clock.now

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (byteStream, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPProbeError.transport("The server did not return an HTTP response.")
            }

            let body = try await Self.read(byteStream, upTo: Self.maxBodyBytes)
            let latency = clock.now - start

            return HTTPProbeResult(
                statusCode: httpResponse.statusCode,
                title: Self.extractTitle(from: Self.decodeBody(body)),
                server: httpResponse.value(forHTTPHeaderField: "Server"),
                location: httpResponse.value(forHTTPHeaderField: "Location"),
                latency: latency
            )
        } catch let error as HTTPProbeError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw HTTPProbeError.timedOut
        } catch {
            throw HTTPProbeError.transport(error.localizedDescription)
        }
    }

    // MARK: - Safety

    static func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw HTTPProbeError.notHTTP
        }
        guard isLoopback(url) else {
            throw HTTPProbeError.notLoopback
        }
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    // MARK: - Transport

    private static func makeSession(timeout: Duration) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = timeout.timeInterval
        // `timeoutIntervalForRequest` only bounds the gap between packets, so a
        // server dripping one byte at a time would hold the probe open forever.
        // The resource timeout is the one that bounds the whole exchange.
        configuration.timeoutIntervalForResource = timeout.timeInterval
        return URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    /// Reads at most `limit` bytes. `bytes(for:)` streams the response instead
    /// of buffering it, so a service that never stops writing never grows
    /// the buffer past the cap.
    private static func read(_ bytes: URLSession.AsyncBytes, upTo limit: Int) async throws -> Data {
        var buffer = Data()
        buffer.reserveCapacity(limit)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= limit { break }
        }
        return buffer
    }

    private static func decodeBody(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: - Title parsing

    /// Bounded manual scan for a `<title>` element. Runs over an already
    /// capped string rather than a regex over the whole body, so a page with
    /// no closing tag still returns in constant time.
    static func extractTitle(from html: String) -> String? {
        guard let tagStart = html.range(of: "<title", options: .caseInsensitive) else { return nil }
        guard let tagEnd = html.range(of: ">", range: tagStart.upperBound..<html.endIndex) else { return nil }

        let contentStart = tagEnd.upperBound
        let contentEnd = html.range(
            of: "</title",
            options: .caseInsensitive,
            range: contentStart..<html.endIndex
        )?.lowerBound ?? html.endIndex

        let collapsed = String(html[contentStart..<contentEnd])
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let decoded = decodeEntities(collapsed)
        return decoded.isEmpty ? nil : decoded
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        // `&amp;` decodes last so a literal `&amp;lt;` becomes `&lt;`, not `<`.
        for (entity, replacement) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")
        ] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}

/// Refuses every redirect, which reports the first response rather than the end of
/// a chain. That is what an inspector wants, it cannot be walked off loopback, and
/// it cannot be trapped in a dev server's redirect loop.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
