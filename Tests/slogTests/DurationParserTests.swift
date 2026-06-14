//
//  DurationParserTests.swift
//  slog
//
//  Created by Alex Maimescu on 03/02/2026.
//

import ArgumentParser
@testable import slog
import Testing

@Suite("Duration Parser Tests")
struct DurationParserTests {
    @Test
    func parseSeconds() throws {
        let result = try DurationParser.parse("5s", optionName: "--timeout")
        #expect(result == 5.0)
    }

    @Test
    func parseSecondsUppercase() throws {
        let result = try DurationParser.parse("10S", optionName: "--timeout")
        #expect(result == 10.0)
    }

    @Test
    func parseMinutes() throws {
        let result = try DurationParser.parse("2m", optionName: "--capture")
        #expect(result == 120.0)
    }

    @Test
    func parseMinutesUppercase() throws {
        let result = try DurationParser.parse("3M", optionName: "--capture")
        #expect(result == 180.0)
    }

    @Test
    func parseHours() throws {
        let result = try DurationParser.parse("1h", optionName: "--timeout")
        #expect(result == 3600.0)
    }

    @Test
    func parseHoursUppercase() throws {
        let result = try DurationParser.parse("2H", optionName: "--timeout")
        #expect(result == 7200.0)
    }

    @Test
    func parseNoSuffix() throws {
        let result = try DurationParser.parse("30", optionName: "--timeout")
        #expect(result == 30.0)
    }

    @Test
    func parseDecimal() throws {
        let result = try DurationParser.parse("1.5m", optionName: "--capture")
        #expect(result == 90.0)
    }

    @Test
    func throwsForEmpty() {
        #expect(throws: ValidationError.self) {
            _ = try DurationParser.parse("", optionName: "--timeout")
        }
    }

    @Test
    func throwsForWhitespace() {
        #expect(throws: ValidationError.self) {
            _ = try DurationParser.parse("   ", optionName: "--timeout")
        }
    }

    @Test
    func throwsForInvalidFormat() {
        #expect(throws: ValidationError.self) {
            _ = try DurationParser.parse("abc", optionName: "--timeout")
        }
    }

    @Test
    func throwsForNegative() {
        #expect(throws: ValidationError.self) {
            _ = try DurationParser.parse("-5s", optionName: "--timeout")
        }
    }

    @Test
    func throwsForZero() {
        #expect(throws: ValidationError.self) {
            _ = try DurationParser.parse("0s", optionName: "--timeout")
        }
    }

    @Test
    func handlesWhitespace() throws {
        let result = try DurationParser.parse("  5s  ", optionName: "--timeout")
        #expect(result == 5.0)
    }
}
