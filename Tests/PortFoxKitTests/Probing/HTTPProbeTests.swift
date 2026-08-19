import Foundation
import Network
import Testing
@testable import PortFoxKit

@Suite("HTTPProbe loopback safety")
struct HTTPProbeLoopbackSafetyTests {
    @Test("a non-loopback URL is rejected before any request is made")
    func nonLoopbackURLIsRejected() async throws {
        let probe = HTTPProbe()
        await #expect(throws: HTTPProbeError.notLoopback) {
            _ = try await probe.probe(URL(string: "http://example.com")!)
        }
    }

    @Test("a non-http scheme is rejected")
    func nonHTTPSchemeIsRejected() async throws {
        let probe = HTTPProbe()
        await #expect(throws: HTTPProbeError.notHTTP) {
            _ = try await probe.probe(URL(string: "ftp://localhost/")!)
        }
    }

    @Test(
        "loopback hosts pass the safety check even when nothing is listening",
        arguments: ["http://127.0.0.1:1/", "http://localhost:1/", "http://[::1]:1/"]
    )
    func loopbackHostsPassSafetyCheck(urlString: String) async throws {
        let probe = HTTPProbe(timeout: .milliseconds(300))
        let url = try #require(URL(string: urlString))

        do {
            _ = try await probe.probe(url)
            Issue.record("expected port 1 to refuse the connection")
        } catch let error as HTTPProbeError {
            #expect(error != .notLoopback)
        }
    }
}

@Suite("HTTPProbe title extraction")
struct HTTPProbeTitleExtractionTests {
    @Test("a plain title")
    func plainTitle() {
        #expect(HTTPProbe.extractTitle(from: "<html><head><title>PortFox</title></head></html>") == "PortFox")
    }

    @Test("a title tag with attributes")
    func titleWithAttributes() {
        let html = "<title data-x=\"1\" class='a'>Dashboard</title>"
        #expect(HTTPProbe.extractTitle(from: html) == "Dashboard")
    }

    @Test("common HTML entities are decoded")
    func entitiesAreDecoded() {
        let html = "<title>Tom &amp; Jerry &lt;live&gt; &quot;show&quot; &#39;now&#39; &apos;here&apos;</title>"
        #expect(HTTPProbe.extractTitle(from: html) == "Tom & Jerry <live> \"show\" 'now' 'here'")
    }

    @Test("a literal double-encoded ampersand decodes once")
    func doubleEncodedAmpersandDecodesOnce() {
        #expect(HTTPProbe.extractTitle(from: "<title>&amp;lt;</title>") == "&lt;")
    }

    @Test("internal whitespace runs collapse to a single space")
    func whitespaceCollapses() {
        let html = "<title>\n  Hello\n   World  \n</title>"
        #expect(HTTPProbe.extractTitle(from: html) == "Hello World")
    }

    @Test("leading and trailing whitespace is trimmed")
    func surroundingWhitespaceIsTrimmed() {
        #expect(HTTPProbe.extractTitle(from: "<title>   Padded   </title>") == "Padded")
    }

    @Test("a missing title returns nil")
    func missingTitleReturnsNil() {
        #expect(HTTPProbe.extractTitle(from: "<html><body>No title here</body></html>") == nil)
    }

    @Test("an empty title returns nil")
    func emptyTitleReturnsNil() {
        #expect(HTTPProbe.extractTitle(from: "<title></title>") == nil)
    }

    @Test("a body truncated mid-title still returns the partial text")
    func truncatedMidTitleReturnsPartialText() {
        #expect(HTTPProbe.extractTitle(from: "<html><head><title>Hello Wor") == "Hello Wor")
    }
}

@Suite("HTTPProbe end to end")
struct HTTPProbeEndToEndTests {
    @Test("probing a real loopback server returns status, title, server header and latency")
    func probesARealServer() async throws {
        let responseBody = "<html><head><title>PortFox Test</title></head><body>hi</body></html>"
        let response = """
        HTTP/1.1 200 OK\r
        Server: PortFoxTestServer/1.0\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(responseBody.utf8.count)\r
        Connection: close\r
        \r
        \(responseBody)
        """

        let server = try LoopbackHTTPServer(response: response)
        let port = try await server.start()
        defer { server.stop() }

        let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))
        let result = try await HTTPProbe(timeout: .seconds(2)).probe(url)

        #expect(result.statusCode == 200)
        #expect(result.title == "PortFox Test")
        #expect(result.server == "PortFoxTestServer/1.0")
        #expect(result.latency > .zero)
    }

    @Test("a redirect is reported rather than followed")
    func redirectIsReportedNotFollowed() async throws {
        let response = """
        HTTP/1.1 302 Found\r
        Location: http://example.com/elsewhere\r
        Content-Length: 0\r
        Connection: close\r
        \r

        """

        let server = try LoopbackHTTPServer(response: response)
        let port = try await server.start()
        defer { server.stop() }

        let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))
        let result = try await HTTPProbe(timeout: .seconds(2)).probe(url)

        #expect(result.statusCode == 302)
        #expect(result.location == "http://example.com/elsewhere")
    }

    @Test("a server that declares a body and then stalls does not hang the probe")
    func stalledBodyTimesOut() async throws {
        // `timeoutIntervalForRequest` alone would not catch this, because the
        // headers arrive promptly and only the body never completes.
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html\r
        Content-Length: 1000000\r
        \r
        <html><head><title>Stalled</title></head><body>
        """

        let server = try LoopbackHTTPServer(response: response, closesConnection: false)
        let port = try await server.start()
        defer { server.stop() }

        let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))
        let clock = ContinuousClock()
        let started = clock.now

        await #expect(throws: HTTPProbeError.timedOut) {
            _ = try await HTTPProbe(timeout: .milliseconds(700)).probe(url)
        }
        #expect(clock.now - started < .seconds(5))
    }

    @Test("a body larger than the cap is truncated rather than read whole")
    func oversizedBodyIsCapped() async throws {
        let filler = String(repeating: "a", count: 200_000)
        let body = "<html><head><title>Capped</title></head><body>\(filler)</body></html>"
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        let server = try LoopbackHTTPServer(response: response)
        let port = try await server.start()
        defer { server.stop() }

        let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))
        let result = try await HTTPProbe(timeout: .seconds(5)).probe(url)

        #expect(result.statusCode == 200)
        #expect(result.title == "Capped")
    }
}

private struct TestServerError: Error {}

/// A single-shot loopback HTTP server used only to exercise `HTTPProbe`
/// end to end. It accepts one connection, writes the canned response, and
/// closes.
private final class LoopbackHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "portfox.tests.http-probe-server")
    private let responseData: Data
    private let closesConnection: Bool

    init(response: String, closesConnection: Bool = true) throws {
        responseData = Data(response.utf8)
        self.closesConnection = closesConnection
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [responseData, closesConnection] connection in
            connection.start(queue: DispatchQueue(label: "portfox.tests.http-probe-connection"))
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    // Leaving it open is how the stalled-body case is simulated.
                    if closesConnection { connection.cancel() }
                })
            }
        }
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        continuation.resume(returning: port.rawValue)
                    } else {
                        continuation.resume(throwing: TestServerError())
                    }
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }
}
