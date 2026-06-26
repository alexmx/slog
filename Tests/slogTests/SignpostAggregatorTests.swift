//
//  SignpostAggregatorTests.swift
//  slog
//
//  Created by Alex Maimescu on 26/06/2026.
//

import Foundation
@testable import slog
import Testing

@Suite("SignpostAggregator Tests")
struct SignpostAggregatorTests {
    /// Fixed base timestamp so durations are deterministic.
    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// Build a signpost `LogEntry` with an offset (seconds) from `base`.
    private func entry(
        name: String,
        id: UInt64,
        type: SignpostType,
        offset: TimeInterval,
        pid: Int = 4242,
        message: String = "",
        subsystem: String? = "com.slog.test",
        category: String? = "signpost"
    ) -> LogEntry {
        LogEntry(
            timestamp: Self.base.addingTimeInterval(offset),
            processName: "emitter",
            pid: pid,
            subsystem: subsystem,
            category: category,
            level: .default,
            message: message,
            eventType: "signpostEvent",
            signpostID: id,
            signpostName: name,
            signpostType: type,
            signpostScope: "process"
        )
    }

    // MARK: - Pairing

    @Test
    func simplePairing() throws {
        var agg = SignpostAggregator()
        agg.ingest(entry(name: "parse.postImage", id: 1, type: .begin, offset: 0, message: "len 208123"))
        agg.ingest(entry(name: "parse.postImage", id: 1, type: .end, offset: 0.045))

        let intervals = agg.intervals()
        #expect(intervals.count == 1)
        let interval = try #require(intervals.first)
        #expect(interval.name == "parse.postImage")
        #expect(interval.isInFlight == false)
        // 45ms, allowing for floating point.
        #expect(abs((interval.durationMs ?? 0) - 45) < 0.001)
        // Args come from the begin event.
        #expect(interval.message == "len 208123")
    }

    @Test
    func concurrentSameNameNotCollapsed() {
        var agg = SignpostAggregator()
        // Two attr.chunk intervals begin at the same instant, distinct IDs.
        agg.ingest(entry(name: "attr.chunk", id: 2, type: .begin, offset: 0, message: "start 0"))
        agg.ingest(entry(name: "attr.chunk", id: 3, type: .begin, offset: 0, message: "start 4096"))
        agg.ingest(entry(name: "attr.chunk", id: 2, type: .end, offset: 0.013))
        agg.ingest(entry(name: "attr.chunk", id: 3, type: .end, offset: 0.018))

        let intervals = agg.intervals()
        #expect(intervals.count == 2)
        #expect(intervals.allSatisfy { $0.name == "attr.chunk" })
        #expect(Set(intervals.map(\.signpostID)) == [2, 3])
        // Each keeps its own begin args and duration.
        let byID = Dictionary(uniqueKeysWithValues: intervals.map { ($0.signpostID, $0) })
        #expect(byID[2]?.message == "start 0")
        #expect(byID[3]?.message == "start 4096")
        #expect(abs((byID[2]?.durationMs ?? 0) - 13) < 0.001)
        #expect(abs((byID[3]?.durationMs ?? 0) - 18) < 0.001)
    }

    @Test
    func sameIDDifferentProcessNotPaired() {
        var agg = SignpostAggregator()
        agg.ingest(entry(name: "work", id: 1, type: .begin, offset: 0, pid: 100))
        agg.ingest(entry(name: "work", id: 1, type: .end, offset: 0.010, pid: 200))

        // The end belongs to a different pid, so the begin stays in-flight and
        // the end is an orphan.
        let intervals = agg.intervals()
        #expect(intervals.count == 1)
        #expect(intervals.first?.isInFlight == true)
        #expect(agg.orphanEndCount == 1)
    }

    // MARK: - Unmatched events

    @Test
    func inFlightBegin() throws {
        var agg = SignpostAggregator()
        agg.ingest(entry(name: "render.draw", id: 4, type: .begin, offset: 0, message: "frame 1"))

        let intervals = agg.intervals()
        #expect(intervals.count == 1)
        let interval = try #require(intervals.first)
        #expect(interval.isInFlight)
        #expect(interval.end == nil)
        #expect(interval.durationMs == nil)
        #expect(interval.message == "frame 1")
    }

    @Test
    func orphanEnd() {
        var agg = SignpostAggregator()
        agg.ingest(entry(name: "ghost", id: 9, type: .end, offset: 0.010))

        #expect(agg.intervals().isEmpty)
        #expect(agg.orphanEndCount == 1)
    }

    @Test
    func eventTypeIgnored() {
        var agg = SignpostAggregator()
        agg.ingest(entry(name: "checkpoint", id: 17_216_892_719_917_625_070, type: .event, offset: 0))

        #expect(agg.intervals().isEmpty)
        #expect(agg.orphanEndCount == 0)
    }

    @Test
    func nonSignpostIgnored() {
        var agg = SignpostAggregator()
        let logLine = LogEntry(
            timestamp: Self.base,
            processName: "app",
            pid: 1,
            subsystem: "com.slog.test",
            category: "general",
            level: .info,
            message: "just a log",
            eventType: "logEvent"
        )
        agg.ingest(logLine)
        #expect(agg.intervals().isEmpty)
    }

    // MARK: - Summaries

    @Test
    func summaryStatistics() throws {
        var agg = SignpostAggregator()
        // Three parse.postImage intervals: 40ms, 42ms, 50ms.
        let durations: [TimeInterval] = [0.040, 0.042, 0.050]
        for (i, d) in durations.enumerated() {
            let id = UInt64(i + 1)
            agg.ingest(entry(name: "parse.postImage", id: id, type: .begin, offset: Double(i)))
            agg.ingest(entry(name: "parse.postImage", id: id, type: .end, offset: Double(i) + d))
        }

        let summaries = agg.summaries()
        #expect(summaries.count == 1)
        let summary = try #require(summaries.first)
        #expect(summary.name == "parse.postImage")
        #expect(summary.count == 3)
        #expect(summary.inFlightCount == 0)
        #expect(abs((summary.minMs ?? 0) - 40) < 0.001)
        #expect(abs((summary.p50Ms ?? 0) - 42) < 0.001) // median of 40,42,50
        #expect(abs((summary.maxMs ?? 0) - 50) < 0.001)
        #expect(abs((summary.totalMs ?? 0) - 132) < 0.001)
    }

    @Test
    func summaryWithInFlight() throws {
        var agg = SignpostAggregator()
        agg.ingest(entry(name: "op", id: 1, type: .begin, offset: 0))
        agg.ingest(entry(name: "op", id: 1, type: .end, offset: 0.020))
        agg.ingest(entry(name: "op", id: 2, type: .begin, offset: 1)) // in-flight

        let summary = try #require(agg.summaries().first)
        #expect(summary.count == 2)
        #expect(summary.inFlightCount == 1)
        #expect(abs((summary.totalMs ?? 0) - 20) < 0.001) // only the completed one
        #expect(abs((summary.maxMs ?? 0) - 20) < 0.001)
    }

    @Test
    func summaryOrdering() {
        var agg = SignpostAggregator()
        // fast: 10ms total; slow: 100ms total.
        agg.ingest(entry(name: "fast", id: 1, type: .begin, offset: 0))
        agg.ingest(entry(name: "fast", id: 1, type: .end, offset: 0.010))
        agg.ingest(entry(name: "slow", id: 2, type: .begin, offset: 0))
        agg.ingest(entry(name: "slow", id: 2, type: .end, offset: 0.100))

        let names = agg.summaries().map(\.name)
        #expect(names == ["slow", "fast"])
    }

    @Test
    func intervalsSortedByStart() {
        var agg = SignpostAggregator()
        agg.ingest(entry(name: "b", id: 2, type: .begin, offset: 1))
        agg.ingest(entry(name: "b", id: 2, type: .end, offset: 1.5))
        agg.ingest(entry(name: "a", id: 1, type: .begin, offset: 0))
        agg.ingest(entry(name: "a", id: 1, type: .end, offset: 0.5))

        let starts = agg.intervals().map(\.start)
        #expect(starts == starts.sorted())
    }
}
