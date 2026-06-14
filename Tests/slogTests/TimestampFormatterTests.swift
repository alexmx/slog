//
//  TimestampFormatterTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("TimestampFormatter Tests")
struct TimestampFormatterTests {
    @Test
    func absoluteMode() throws {
        let formatter = TimestampFormatter(mode: .absolute)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(
            year: 2026, month: 2, day: 5,
            hour: 14, minute: 30, second: 45, nanosecond: 123_000_000
        )
        let date = try #require(calendar.date(from: components))

        let result = formatter.format(date)
        #expect(result == "14:30:45.123")
    }

    @Test
    func relativeFirstEntry() {
        let formatter = TimestampFormatter(mode: .relative)
        let date = Date()

        let result = formatter.format(date)
        #expect(result == "+0.000s")
    }

    @Test
    func relativeDelta() {
        let formatter = TimestampFormatter(mode: .relative)
        let base = Date()

        _ = formatter.format(base)
        let result = formatter.format(base.addingTimeInterval(0.312))
        #expect(result == "+0.312s")
    }

    @Test
    func relativeSeconds() {
        let formatter = TimestampFormatter(mode: .relative)
        let base = Date()

        _ = formatter.format(base)
        let result = formatter.format(base.addingTimeInterval(5.5))
        #expect(result == "+5.500s")
    }

    @Test
    func relativeMinutes() {
        let formatter = TimestampFormatter(mode: .relative)
        let base = Date()

        _ = formatter.format(base)
        let result = formatter.format(base.addingTimeInterval(125))
        #expect(result == "+2m05.00s")
    }

    @Test
    func relativeHours() {
        let formatter = TimestampFormatter(mode: .relative)
        let base = Date()

        _ = formatter.format(base)
        let result = formatter.format(base.addingTimeInterval(3723))
        #expect(result == "+1h02m")
    }

    @Test
    func relativeRunningDelta() {
        let formatter = TimestampFormatter(mode: .relative)
        let base = Date()

        _ = formatter.format(base)
        _ = formatter.format(base.addingTimeInterval(1.0))
        let result = formatter.format(base.addingTimeInterval(1.5))
        #expect(result == "+0.500s")
    }
}
