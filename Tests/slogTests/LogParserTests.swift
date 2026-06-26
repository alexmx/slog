//
//  LogParserTests.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation
@testable import slog
import Testing

@Suite("LogParser Tests")
struct LogParserTests {
    let parser = LogParser()

    @Test
    func parseValidNDJSON() {
        let json = """
        {"timestamp":"2024-01-15T10:30:45.123456Z","processImagePath":"/Applications/Finder.app/Contents/MacOS/Finder","processID":1234,"senderImagePath":"/usr/lib/libnetwork.dylib","subsystem":"com.apple.finder","category":"default","messageType":"Info","eventType":"logEvent","eventMessage":"Test message","source":{"symbol":"-[MyClass doThing]","file":"MyFile.swift","line":42,"image":"MyFramework"}}
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
        #expect(entry?.source == "MyFramework -[MyClass doThing] MyFile.swift:42")
    }

    @Test
    func parseMissingOptionalFields() {
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

    @Test
    func parseEmptyLine() {
        let entry = parser.parse(line: "")
        #expect(entry == nil)
    }

    @Test
    func parseWhitespaceLine() {
        let entry = parser.parse(line: "   \n\t  ")
        #expect(entry == nil)
    }

    @Test
    func parseSignpostBeginEvent() {
        // Real NDJSON shape captured from `log show --signpost --style ndjson`.
        let json = """
        {"timestamp":"2026-06-26 13:23:32.715547+0100","processImagePath":"/usr/bin/emitter","processID":4242,"subsystem":"com.slog.test","category":"signpost","eventType":"signpostEvent","eventMessage":"len 208123 batch=1","signpostID":1,"signpostName":"parse.postImage","signpostType":"begin","signpostScope":"process"}
        """

        let entry = parser.parse(line: json)

        #expect(entry?.eventType == "signpostEvent")
        #expect(entry?.signpostID == 1)
        #expect(entry?.signpostName == "parse.postImage")
        #expect(entry?.signpostType == .begin)
        #expect(entry?.signpostScope == "process")
        // Args ride on the begin event.
        #expect(entry?.message == "len 208123 batch=1")
    }

    @Test
    func parseSignpostEndHasEmptyMessage() {
        let json = """
        {"timestamp":"2026-06-26 13:23:32.760000+0100","processImagePath":"/usr/bin/emitter","processID":4242,"subsystem":"com.slog.test","category":"signpost","eventType":"signpostEvent","eventMessage":"","signpostID":1,"signpostName":"parse.postImage","signpostType":"end","signpostScope":"process"}
        """

        let entry = parser.parse(line: json)

        #expect(entry?.signpostType == .end)
        #expect(entry?.message == "")
    }

    @Test
    func parseSignpostEventIDExceedingInt64() {
        // `emitEvent` IDs use the exclusive ID, which overflows Int64.
        let json = """
        {"timestamp":"2026-06-26 13:23:32.778000+0100","processImagePath":"/usr/bin/emitter","processID":4242,"subsystem":"com.slog.test","category":"signpost","eventType":"signpostEvent","eventMessage":"phase init","signpostID":17216892719917625070,"signpostName":"checkpoint","signpostType":"event","signpostScope":"process"}
        """

        let entry = parser.parse(line: json)

        #expect(entry?.signpostID == 17_216_892_719_917_625_070)
        #expect(entry?.signpostType == .event)
    }

    @Test
    func parseNonSignpostHasNilSignpostFields() {
        let json = """
        {"timestamp":"2024-01-15T10:30:45Z","processImagePath":"/usr/bin/test","processID":1,"messageType":"Info","eventType":"logEvent","eventMessage":"hi"}
        """

        let entry = parser.parse(line: json)

        #expect(entry?.signpostID == nil)
        #expect(entry?.signpostName == nil)
        #expect(entry?.signpostType == nil)
        #expect(entry?.signpostScope == nil)
    }

    @Test
    func parseInvalidJSON() {
        let entry = parser.parse(line: "not valid json {}")
        // May return nil or attempt legacy parsing
        // Just ensure it doesn't crash
        _ = entry
    }

    @Test
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

    @Test
    func parseAllLogLevels() {
        let levels = ["Debug", "Info", "Default", "Error", "Fault"]
        let expectedLevels: [LogLevel] = [.debug, .info, .default, .error, .fault]

        for (levelStr, expectedLevel) in zip(levels, expectedLevels) {
            let json = """
            {"timestamp":"2024-01-15T10:30:45Z","processImagePath":"/bin/test","processID":1,"messageType":"\(
                levelStr
            )","eventMessage":"Test"}
            """

            let entry = parser.parse(line: json)
            #expect(entry?.level == expectedLevel, "Expected level \(expectedLevel) for \(levelStr)")
        }
    }
}

@Suite("LogLevel Tests")
struct LogLevelTests {
    @Test
    func levelComparison() {
        #expect(LogLevel.debug < LogLevel.info)
        #expect(LogLevel.info < LogLevel.default)
        #expect(LogLevel.default < LogLevel.error)
        #expect(LogLevel.error < LogLevel.fault)
    }

    @Test
    func levelFromString() {
        #expect(LogLevel(string: "debug") == .debug)
        #expect(LogLevel(string: "DEBUG") == .debug)
        #expect(LogLevel(string: "Info") == .info)
        #expect(LogLevel(string: "error") == .error)
        #expect(LogLevel(string: "FAULT") == .fault)
        #expect(LogLevel(string: "invalid") == nil)
    }
}
