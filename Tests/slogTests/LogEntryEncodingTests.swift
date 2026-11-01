//
//  LogEntryEncodingTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing
import ToonFormat

@Suite("LogEntry Encoding Tests")
struct LogEntryEncodingTests {
    private let timestamp = Date(timeIntervalSince1970: 1_000_000)

    private func makeEntry(signpost: Bool = false) -> LogEntry {
        LogEntry(
            timestamp: timestamp,
            processName: "TestApp",
            pid: 1234,
            subsystem: "com.test.app",
            category: nil,
            level: .error,
            message: "Something went wrong",
            threadID: 100,
            eventType: signpost ? "signpostEvent" : "logEvent",
            signpostID: signpost ? 7 : nil,
            signpostName: signpost ? "render.draw" : nil,
            signpostType: signpost ? .begin : nil,
            signpostScope: signpost ? "process" : nil
        )
    }

    private func jsonObject(_ entry: LogEntry) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test
    func usesTheCLIKeyNames() throws {
        let json = try jsonObject(makeEntry())
        #expect(json["process"] as? String == "TestApp")
        #expect(json["processName"] == nil)
        #expect(json["pid"] as? Int == 1234)
        #expect(json["level"] as? String == "Error")
        #expect(json["message"] as? String == "Something went wrong")
        #expect(json["threadID"] as? Int == 100)
    }

    @Test
    func absentOptionalsAreOmitted() throws {
        let json = try jsonObject(makeEntry())
        #expect(json["category"] == nil)
        #expect(json["source"] == nil)
        #expect(json["signpostID"] == nil)
    }

    @Test
    func signpostFieldsAppearWhenSet() throws {
        let json = try jsonObject(makeEntry(signpost: true))
        #expect(json["signpostID"] as? Int == 7)
        #expect(json["signpostName"] as? String == "render.draw")
        #expect(json["signpostType"] as? String == "begin")
        #expect(json["signpostScope"] as? String == "process")
    }

    @Test
    func toonOmitsSignpostFieldsWhenAbsent() throws {
        let toon = try String(decoding: TOONEncoder().encode(makeEntry()), as: UTF8.self)
        #expect(toon.contains("process: TestApp"))
        #expect(!toon.contains("signpost"))
    }

    @Test
    func spillRoundTripsIncludingSignpostFields() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for entry in [makeEntry(), makeEntry(signpost: true)] {
            let decoded = try decoder.decode(LogEntry.self, from: encoder.encode(entry))
            #expect(decoded == entry)
        }
    }
}
