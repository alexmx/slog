//
//  SignpostFormatterTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("SignpostFormatter Tests")
struct SignpostFormatterTests {
    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func interval(
        name: String,
        id: UInt64,
        durationMs: Double?,
        message: String
    ) -> SignpostInterval {
        SignpostInterval(
            name: name,
            subsystem: "com.slog.test",
            category: "signpost",
            pid: 1,
            signpostID: id,
            start: Self.base,
            end: durationMs.map { Self.base.addingTimeInterval($0 / 1000) },
            durationMs: durationMs,
            message: message
        )
    }

    private func aggregate(_ intervals: [SignpostInterval]) -> [SignpostSummary] {
        var agg = SignpostAggregator()
        // Re-feed begins/ends so the aggregator produces summaries.
        for i in intervals {
            let begin = LogEntry(
                timestamp: i.start,
                processName: "p",
                pid: i.pid,
                subsystem: i.subsystem,
                category: i.category,
                level: .default,
                message: i.message,
                eventType: "signpostEvent",
                signpostID: i.signpostID,
                signpostName: i.name,
                signpostType: .begin
            )
            agg.ingest(begin)
            if let end = i.end {
                agg.ingest(LogEntry(
                    timestamp: end,
                    processName: "p",
                    pid: i.pid,
                    subsystem: i.subsystem,
                    category: i.category,
                    level: .default,
                    message: "",
                    eventType: "signpostEvent",
                    signpostID: i.signpostID,
                    signpostName: i.name,
                    signpostType: .end
                ))
            }
        }
        return agg.summaries()
    }

    @Test
    func rendersHeaderAndRow() {
        let summaries = aggregate([
            interval(name: "parse.postImage", id: 1, durationMs: 42, message: "len 208123")
        ])
        let table = SignpostFormatter.renderTable(summaries)

        #expect(table.contains("interval"))
        #expect(table.contains("parse.postImage"))
        #expect(table.contains("len 208123"))
        #expect(table.contains("42.0ms"))
    }

    @Test
    func notesInFlightOccurrences() {
        let summaries = aggregate([
            interval(name: "render.draw", id: 1, durationMs: nil, message: "frame 1")
        ])
        let table = SignpostFormatter.renderTable(summaries)

        #expect(table.contains("in-flight"))
        // No duration available — rendered as a dash.
        #expect(table.contains("-"))
    }

    @Test
    func notesOrphanEnds() {
        let summaries = aggregate([
            interval(name: "op", id: 1, durationMs: 10, message: "x")
        ])
        let table = SignpostFormatter.renderTable(summaries, orphanEndCount: 2)

        #expect(table.contains("2 orphaned ends"))
    }

    @Test
    func emptySummariesShowsHint() {
        let table = SignpostFormatter.renderTable([])

        #expect(table.contains("No signpost intervals found"))
        #expect(table.contains("persist:debug"))
    }

    @Test
    func formatMsCompactsLargeValues() {
        #expect(SignpostFormatter.formatMs(128) == "128ms")
        #expect(SignpostFormatter.formatMs(1.1) == "1.1ms")
        #expect(SignpostFormatter.formatMs(nil) == "-")
    }

    // MARK: - Structured formats

    @Test
    func jsonFormatEmitsStructuredFields() throws {
        let summaries = aggregate([
            interval(name: "parse.postImage", id: 1, durationMs: 42, message: "len 208123")
        ])
        let json = SignpostFormatter.render(summaries, format: .json)

        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        let first = try #require(parsed?.first)
        #expect(first["name"] as? String == "parse.postImage")
        #expect(first["total_ms"] as? Double == 42)
        #expect(first["in_flight"] as? Int == 0)
        // Occurrences are included in the CLI JSON variant.
        let occurrences = try #require(first["occurrences"] as? [[String: Any]])
        #expect(occurrences.first?["message"] as? String == "len 208123")
    }

    @Test
    func jsonOmitsNilStatsForInFlightOnly() throws {
        let summaries = aggregate([
            interval(name: "render.draw", id: 1, durationMs: nil, message: "frame 1")
        ])
        let json = SignpostFormatter.render(summaries, format: .json)

        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        let first = try #require(parsed?.first)
        // All occurrences in-flight → duration stats absent, not null.
        #expect(first["total_ms"] == nil)
        #expect(first["p50_ms"] == nil)
        #expect(first["in_flight"] as? Int == 1)
    }

    @Test
    func toonFormatRendersRows() {
        let summaries = aggregate([
            interval(name: "op", id: 1, durationMs: 10, message: "x")
        ])
        let toon = SignpostFormatter.render(summaries, format: .toon)

        #expect(toon.contains("name: op"))
        #expect(toon.contains("total_ms"))
    }

    @Test
    func roundTrimsFloatingNoise() {
        #expect(FormattedSignpost.round(42.0000001) == 42)
        #expect(FormattedSignpost.round(1.23456) == 1.235)
        #expect(FormattedSignpost.round(nil) == nil)
    }
}
