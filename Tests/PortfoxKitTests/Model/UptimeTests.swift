import Foundation
import Testing
@testable import PortfoxKit

@Suite("uptime")
struct UptimeTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func started(_ secondsAgo: Int) -> Date {
        now.addingTimeInterval(-Double(secondsAgo))
    }

    // MARK: - Duration, for a list row

    @Test("each unit takes over at its own boundary")
    func units() {
        #expect(Uptime.duration(since: started(10), now: now) == "10s")
        #expect(Uptime.duration(since: started(59), now: now) == "59s")
        #expect(Uptime.duration(since: started(60), now: now) == "1m")
        #expect(Uptime.duration(since: started(3599), now: now) == "59m")
        #expect(Uptime.duration(since: started(3600), now: now) == "1h")
        #expect(Uptime.duration(since: started(86_399), now: now) == "23h")
        #expect(Uptime.duration(since: started(86_400), now: now) == "1d")
        #expect(Uptime.duration(since: started(86_400 * 21), now: now) == "21d")
    }

    /// A row redraws only when the scan behind it moves, so a counter ticking
    /// through single seconds would sit frozen at whatever it read anyway.
    @Test("a service younger than ten seconds shows nothing at all")
    func tooYoung() {
        #expect(Uptime.duration(since: started(0), now: now) == nil)
        #expect(Uptime.duration(since: started(9), now: now) == nil)
    }

    /// Clocks move backwards over a daylight saving change and an NTP correction.
    @Test("a start time in the future shows nothing rather than a negative")
    func futureStart() {
        #expect(Uptime.duration(since: started(-500), now: now) == nil)
    }

    // MARK: - Label, for the dashboard header

    @Test("the header reads as a moment in the past")
    func label() {
        #expect(Uptime.label(since: started(90), now: now) == "1m ago")
        #expect(Uptime.label(since: started(86_400 * 3), now: now) == "3d ago")
    }

    @Test("the header says something even when the row would say nothing")
    func labelTooYoung() {
        #expect(Uptime.label(since: started(2), now: now) == "just now")
    }
}
