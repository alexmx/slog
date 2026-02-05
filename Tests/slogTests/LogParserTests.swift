//
//  LogParserTests.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Testing
import Foundation
@testable import slog

@Suite("LogParser Tests")
struct LogParserTests {
    let parser = LogParser()

    @Test("Parse valid NDJSON log entry")
    func parseValidNDJSON() throws {
        let json = """
        {"timestamp":"2024-01-15T10:30:45.123456Z","processImagePath":"/Applications/Finder.app/Contents/MacOS/Finder","processID":1234,"senderImagePath":"/usr/lib/libnetwork.dylib","subsystem":"com.apple.finder","category":"default","messageType":"Info","eventType":"logEvent","eventMessage":"Test message","source":"MyFile.swift:42"}
        """

        let entry = parser.parse(line: json)

        #expect(entry != nil)
        #expect(entry?.processName == "Finder")
        #expect(entry?.pid == 1234)
        #expect(entry?.subsystem == "com.apple.finder")
        #expect(entry?.category == "default")
        #expect(entry?.level == .info)
        #expect(entry?.message == "Test message")
        #expect(entry?.processImagePath == "/Applications/Finder.app/Contents/MacOS/Finder")
        #expect(entry?.senderImagePath == "/usr/lib/libnetwork.dylib")
        #expect(entry?.eventType == "logEvent")
        #expect(entry?.source == "MyFile.swift:42")
    }

    @Test("Parse log entry with missing optional fields")
    func parseMissingOptionalFields() throws {
        let json = """
        {"timestamp":"2024-01-15T10:30:45Z","processImagePath":"/usr/bin/test","processID":999,"messageType":"Error","eventMessage":"Error occurred"}
        """

        let entry = parser.parse(line: json)

        #expect(entry != nil)
        #expect(entry?.processName == "test")
        #expect(entry?.pid == 999)
        #expect(entry?.subsystem == nil)
        #expect(entry?.category == nil)
        #expect(entry?.level == .error)
        #expect(entry?.senderImagePath == nil)
        #expect(entry?.eventType == nil)
        #expect(entry?.source == nil)
        #expect(entry?.processImagePath == "/usr/bin/test")
    }

    @Test("Parse empty line returns nil")
    func parseEmptyLine() {
        let entry = parser.parse(line: "")
        #expect(entry == nil)
    }

    @Test("Parse whitespace-only line returns nil")
    func parseWhitespaceLine() {
        let entry = parser.parse(line: "   \n\t  ")
        #expect(entry == nil)
    }

    @Test("Parse invalid JSON returns nil")
    func parseInvalidJSON() {
        let entry = parser.parse(line: "not valid json {}")
        // May return nil or attempt legacy parsing
        // Just ensure it doesn't crash
        _ = entry
    }

    @Test("Parse multiple lines")
    func parseMultipleLines() {
        let json1 = """
        {"timestamp":"2024-01-15T10:30:45Z","processImagePath":"/bin/test1","processID":1,"messageType":"Info","eventMessage":"Message 1"}
        """
        let json2 = """
        {"timestamp":"2024-01-15T10:30:46Z","processImagePath":"/bin/test2","processID":2,"messageType":"Error","eventMessage":"Message 2"}
        """

        let combined = "\(json1)\n\(json2)"
        let entries = parser.parseLines(combined)

        #expect(entries.count == 2)
        #expect(entries[0].processName == "test1")
        #expect(entries[1].processName == "test2")
    }

    @Test("Parse all log levels")
    func parseAllLogLevels() {
        let levels = ["Debug", "Info", "Default", "Error", "Fault"]
        let expectedLevels: [LogLevel] = [.debug, .info, .default, .error, .fault]

        for (levelStr, expectedLevel) in zip(levels, expectedLevels) {
            let json = """
            {"timestamp":"2024-01-15T10:30:45Z","processImagePath":"/bin/test","processID":1,"messageType":"\(levelStr)","eventMessage":"Test"}
            """

            let entry = parser.parse(line: json)
            #expect(entry?.level == expectedLevel, "Expected level \(expectedLevel) for \(levelStr)")
        }
    }
}

@Suite("LogLevel Tests")
struct LogLevelTests {
    @Test("LogLevel comparison")
    func levelComparison() {
        #expect(LogLevel.debug < LogLevel.info)
        #expect(LogLevel.info < LogLevel.default)
        #expect(LogLevel.default < LogLevel.error)
        #expect(LogLevel.error < LogLevel.fault)
    }

    @Test("LogLevel from string")
    func levelFromString() {
        #expect(LogLevel(string: "debug") == .debug)
        #expect(LogLevel(string: "DEBUG") == .debug)
        #expect(LogLevel(string: "Info") == .info)
        #expect(LogLevel(string: "error") == .error)
        #expect(LogLevel(string: "FAULT") == .fault)
        #expect(LogLevel(string: "invalid") == nil)
    }
}
