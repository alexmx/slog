//
//  TimestampFormatterTests.swift
//  slog
//

import Testing
import Foundation
@testable import slog

@Suite("TimestampFormatter Tests")
struct TimestampFormatterTests {

    @Test("Absolute mode formats as HH:mm:ss.SSS")
    func absoluteMode() {
        let formatter = TimestampFormatter(mode: .absolute)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(
            year: 2026, month: 2, day: 5,
            hour: 14, minute: 30, second: 45, nanosecond: 123_000_000
        )
        let date = calendar.date(from: components)!

        let result = formatter.format(date)
        #expect(result == "14:30:45.123")
    }

    @Test("Relative mode shows +0.000s for first entry")
    func relativeFirstEntry() {
        let formatter = TimestampFormatter(mode: .relative)
        let date = Date()

        let result = formatter.format(date)
        #expect(result == "+0.000s")
    }

    @Test("Relative mode shows delta for subsequent entries")
    func relativeDelta() {
        let formatter = TimestampFormatter(mode: .relative)
        let base = Date()

        _ = formatter.format(base)
        let result = formatter.format(base.addingTimeInterval(0.312))
        #expect(result == "+0.312s")
    }

    @Test("Relative mode shows seconds for sub-minute deltas")
    func relativeSeconds() {
        let formatter = TimestampFormatter(mode: .relative)
        let base = Date()

        _ = formatter.format(base)
        let result = formatter.format(base.addingTimeInterval(5.5))
        #expect(result == "+5.500s")
    }

    @Test("Relative mode shows minutes for >= 60s deltas")
    func relativeMinutes() {
        let formatter = TimestampFormatter(mode: .relative)
        let base = Date()

        _ = formatter.format(base)
        let result = formatter.format(base.addingTimeInterval(125))
        #expect(result == "+2m05.00s")
    }

    @Test("Relative mode shows hours for >= 3600s deltas")
    func relativeHours() {
        let formatter = TimestampFormatter(mode: .relative)
        let base = Date()

        _ = formatter.format(base)
        let result = formatter.format(base.addingTimeInterval(3723))
        #expect(result == "+1h02m")
    }

    @Test("Relative mode tracks running delta between consecutive entries")
    func relativeRunningDelta() {
        let formatter = TimestampFormatter(mode: .relative)
        let base = Date()

        _ = formatter.format(base)
        _ = formatter.format(base.addingTimeInterval(1.0))
        let result = formatter.format(base.addingTimeInterval(1.5))
        #expect(result == "+0.500s")
    }
}
