//
//  FormattedEntryTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("FormattedEntry Tests")
struct FormattedEntryTests {
    let timestamp = Date(timeIntervalSince1970: 1_000_000)

    func makeEntry(
        subsystem: String? = "com.test.app",
        category: String? = "general",
        threadID: Int? = 100,
        activityID: Int? = 200,
        traceID: Int? = 300,
        processImagePath: String? = "/usr/bin/TestApp",
        senderImagePath: String? = "/usr/lib/libSystem.dylib",
        eventType: String? = "logEvent",
        source: String? = "main.swift:42"
    ) -> LogEntry {
        LogEntry(
            timestamp: timestamp,
            processName: "TestApp",
            pid: 1234,
            subsystem: subsystem,
            category: category,
            level: .error,
            message: "Something went wrong",
            threadID: threadID,
            activityID: activityID,
            traceID: traceID,
            processImagePath: processImagePath,
            senderImagePath: senderImagePath,
            eventType: eventType,
            source: source
        )
    }

    @Test("Maps all fields from LogEntry")
    func mapsAllFields() {
        let entry = makeEntry()
        let formatted = FormattedEntry(from: entry)

        #expect(formatted.timestamp == timestamp)
        #expect(formatted.process == "TestApp")
        #expect(formatted.pid == 1234)
        #expect(formatted.level == "Error")
        #expect(formatted.message == "Something went wrong")
        #expect(formatted.subsystem == "com.test.app")
        #expect(formatted.category == "general")
        #expect(formatted.threadID == 100)
        #expect(formatted.activityID == 200)
        #expect(formatted.traceID == 300)
        #expect(formatted.processImagePath == "/usr/bin/TestApp")
        #expect(formatted.senderImagePath == "/usr/lib/libSystem.dylib")
        #expect(formatted.eventType == "logEvent")
        #expect(formatted.source == "main.swift:42")
    }

    @Test("Handles nil optional fields")
    func handlesNilFields() {
        let entry = makeEntry(
            subsystem: nil, category: nil,
            threadID: nil, activityID: nil,
            traceID: nil,
            processImagePath: nil, senderImagePath: nil,
            eventType: nil, source: nil
        )
        let formatted = FormattedEntry(from: entry)

        #expect(formatted.subsystem == nil)
        #expect(formatted.category == nil)
        #expect(formatted.threadID == nil)
        #expect(formatted.activityID == nil)
        #expect(formatted.traceID == nil)
        #expect(formatted.processImagePath == nil)
        #expect(formatted.senderImagePath == nil)
        #expect(formatted.eventType == nil)
        #expect(formatted.source == nil)
    }

    @Test("JSON encoding produces valid JSON")
    func jsonEncoding() throws {
        let entry = makeEntry()
        let formatted = FormattedEntry(from: entry)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(formatted)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"process\":\"TestApp\""))
        #expect(json.contains("\"pid\":1234"))
        #expect(json.contains("\"level\":\"Error\""))
        #expect(json.contains("\"message\":\"Something went wrong\""))
        #expect(json.contains("\"subsystem\":\"com.test.app\""))
    }

    @Test("JSON encoding omits null fields")
    func jsonEncodingNilFields() throws {
        let entry = makeEntry(
            subsystem: nil, category: nil,
            threadID: nil, activityID: nil,
            processImagePath: nil, senderImagePath: nil,
            eventType: nil, source: nil
        )
        let formatted = FormattedEntry(from: entry)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(formatted)
        let json = try #require(String(data: data, encoding: .utf8))

        // null fields should still appear as null in JSON (default Encodable behavior)
        #expect(json.contains("\"process\":\"TestApp\""))
        #expect(json.contains("\"pid\":1234"))
    }

    @Test("Level string matches LogLevel rawValue")
    func levelStringMapping() {
        let levels: [(LogLevel, String)] = [
            (.debug, "Debug"),
            (.info, "Info"),
            (.default, "Default"),
            (.error, "Error"),
            (.fault, "Fault")
        ]

        for (level, expected) in levels {
            let entry = LogEntry(
                timestamp: timestamp, processName: "Test", pid: 1,
                subsystem: nil, category: nil, level: level,
                message: "msg"
            )
            let formatted = FormattedEntry(from: entry)
            #expect(formatted.level == expected)
        }
    }
}
