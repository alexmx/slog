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
    @Test("Parses seconds with 's' suffix")
    func parseSeconds() throws {
        let result = try DurationParser.parse("5s", optionName: "--timeout")
        #expect(result == 5.0)
    }

    @Test("Parses seconds with uppercase 'S' suffix")
    func parseSecondsUppercase() throws {
        let result = try DurationParser.parse("10S", optionName: "--timeout")
        #expect(result == 10.0)
    }

    @Test("Parses minutes with 'm' suffix")
    func parseMinutes() throws {
        let result = try DurationParser.parse("2m", optionName: "--capture")
        #expect(result == 120.0)
    }

    @Test("Parses minutes with uppercase 'M' suffix")
    func parseMinutesUppercase() throws {
        let result = try DurationParser.parse("3M", optionName: "--capture")
        #expect(result == 180.0)
    }

    @Test("Parses hours with 'h' suffix")
    func parseHours() throws {
        let result = try DurationParser.parse("1h", optionName: "--timeout")
        #expect(result == 3600.0)
    }

    @Test("Parses hours with uppercase 'H' suffix")
    func parseHoursUppercase() throws {
        let result = try DurationParser.parse("2H", optionName: "--timeout")
        #expect(result == 7200.0)
    }

    @Test("Parses number without suffix as seconds")
    func parseNoSuffix() throws {
        let result = try DurationParser.parse("30", optionName: "--timeout")
        #expect(result == 30.0)
    }

    @Test("Parses decimal values")
    func parseDecimal() throws {
        let result = try DurationParser.parse("1.5m", optionName: "--capture")
        #expect(result == 90.0)
    }

    @Test("Throws error for empty string")
    func throwsForEmpty() {
        #expect(throws: ValidationError.self) {
            _ = try DurationParser.parse("", optionName: "--timeout")
        }
    }

    @Test("Throws error for whitespace only")
    func throwsForWhitespace() {
        #expect(throws: ValidationError.self) {
            _ = try DurationParser.parse("   ", optionName: "--timeout")
        }
    }

    @Test("Throws error for invalid format")
    func throwsForInvalidFormat() {
        #expect(throws: ValidationError.self) {
            _ = try DurationParser.parse("abc", optionName: "--timeout")
        }
    }

    @Test("Throws error for negative value")
    func throwsForNegative() {
        #expect(throws: ValidationError.self) {
            _ = try DurationParser.parse("-5s", optionName: "--timeout")
        }
    }

    @Test("Throws error for zero value")
    func throwsForZero() {
        #expect(throws: ValidationError.self) {
            _ = try DurationParser.parse("0s", optionName: "--timeout")
        }
    }

    @Test("Handles whitespace around value")
    func handlesWhitespace() throws {
        let result = try DurationParser.parse("  5s  ", optionName: "--timeout")
        #expect(result == 5.0)
    }
}
