//
//  SignpostAggregator.swift
//  slog
//
//  Created by Alex Maimescu on 26/06/2026.
//

import Foundation

/// A single `os_signpost` interval, reconstructed by pairing a begin event with
/// its matching end event.
///
/// Concurrent intervals sharing a name are kept distinct via `signpostID`. When
/// an end never arrives within the captured window the interval is *in-flight*:
/// `end` and `durationMs` are `nil` rather than being dropped.
public struct SignpostInterval: Sendable, Equatable {
    /// Signpost name (e.g., "parse.postImage").
    public let name: String
    public let subsystem: String?
    public let category: String?
    /// Owning process — part of the pairing key so IDs can't collide across processes.
    public let pid: Int
    public let signpostID: UInt64
    /// Begin timestamp.
    public let start: Date
    /// End timestamp, or `nil` while in-flight.
    public let end: Date?
    /// `end - start` in milliseconds, or `nil` while in-flight.
    public let durationMs: Double?
    /// Interpolated arguments — carried from the begin event (the end event's
    /// message is empty).
    public let message: String

    /// Whether the interval is still open (no matching end was seen).
    public var isInFlight: Bool {
        end == nil
    }

    public init(
        name: String,
        subsystem: String?,
        category: String?,
        pid: Int,
        signpostID: UInt64,
        start: Date,
        end: Date?,
        durationMs: Double?,
        message: String
    ) {
        self.name = name
        self.subsystem = subsystem
        self.category = category
        self.pid = pid
        self.signpostID = signpostID
        self.start = start
        self.end = end
        self.durationMs = durationMs
        self.message = message
    }
}

/// Per-name aggregate over a set of intervals: occurrence count plus duration
/// statistics computed across the completed (non-in-flight) occurrences.
public struct SignpostSummary: Sendable, Equatable {
    public let name: String
    public let subsystem: String?
    public let category: String?
    /// Total occurrences, including in-flight ones.
    public let count: Int
    /// Number of in-flight (unpaired) occurrences.
    public let inFlightCount: Int
    /// Duration statistics over completed occurrences (`nil` when all are in-flight).
    public let minMs: Double?
    public let p50Ms: Double?
    public let maxMs: Double?
    public let totalMs: Double?
    /// Occurrences in begin order.
    public let occurrences: [SignpostInterval]
}

/// Pairs `os_signpost` begin/end events into intervals and aggregates them by name.
///
/// Feed it parsed `LogEntry` values (in any order — events are matched by key,
/// not arrival order); non-signpost entries are ignored. Read results with
/// `intervals()` / `summaries()`, typically after all entries are ingested so
/// that in-flight intervals are surfaced correctly.
public struct SignpostAggregator: Sendable {
    /// Pairing key: a signpost ID is only unique within a process, so the
    /// process and name are part of the key as well.
    private struct Key: Hashable {
        let pid: Int
        let name: String
        let id: UInt64
    }

    /// Open begins awaiting an end, keyed for O(1) pairing.
    private var pending: [Key: LogEntry] = [:]
    /// Completed intervals, in end-arrival order.
    private var completed: [SignpostInterval] = []
    /// End events that arrived with no matching begin (begin fell outside the
    /// captured window). Tracked for diagnostics; can't form an interval.
    public private(set) var orphanEndCount: Int = 0

    public init() {}

    /// Ingest a single parsed log entry. Non-signpost entries are ignored.
    public mutating func ingest(_ entry: LogEntry) {
        guard entry.eventType == "signpostEvent",
              let type = entry.signpostType,
              let name = entry.signpostName,
              let id = entry.signpostID
        else { return }

        let key = Key(pid: entry.pid, name: name, id: id)

        switch type {
        case .begin:
            // A reused key would orphan the previous begin; the latest begin wins.
            pending[key] = entry
        case .end:
            if let begin = pending.removeValue(forKey: key) {
                completed.append(makeInterval(begin: begin, end: entry))
            } else {
                orphanEndCount += 1
            }
        case .event:
            break // standalone marker, not an interval
        }
    }

    /// Ingest a sequence of entries.
    public mutating func ingest(_ entries: some Sequence<LogEntry>) {
        for entry in entries {
            ingest(entry)
        }
    }

    /// All intervals — completed plus any still-open begins as in-flight —
    /// sorted by start time.
    public func intervals() -> [SignpostInterval] {
        let inFlight = pending.values.map { begin in
            SignpostInterval(
                name: begin.signpostName ?? "",
                subsystem: begin.subsystem,
                category: begin.category,
                pid: begin.pid,
                signpostID: begin.signpostID ?? 0,
                start: begin.timestamp,
                end: nil,
                durationMs: nil,
                message: begin.message
            )
        }
        return (completed + inFlight).sorted { lhs, rhs in
            lhs.start < rhs.start
        }
    }

    /// Intervals grouped by name, each with duration statistics. Groups are
    /// ordered by descending total duration (busiest interval first).
    public func summaries() -> [SignpostSummary] {
        let grouped = Dictionary(grouping: intervals(), by: \.name)

        return grouped.map { name, occurrences in
            let sorted = occurrences.sorted { $0.start < $1.start }
            let durations = sorted.compactMap(\.durationMs).sorted()
            let first = sorted.first

            return SignpostSummary(
                name: name,
                subsystem: first?.subsystem,
                category: first?.category,
                count: sorted.count,
                inFlightCount: sorted.count { $0.isInFlight },
                minMs: durations.first,
                p50Ms: Self.median(of: durations),
                maxMs: durations.last,
                totalMs: durations.isEmpty ? nil : durations.reduce(0, +),
                occurrences: sorted
            )
        }
        .sorted { ($0.totalMs ?? 0, $0.name) > ($1.totalMs ?? 0, $1.name) }
    }

    // MARK: - Helpers

    private func makeInterval(begin: LogEntry, end: LogEntry) -> SignpostInterval {
        let durationMs = end.timestamp.timeIntervalSince(begin.timestamp) * 1000
        return SignpostInterval(
            name: begin.signpostName ?? "",
            subsystem: begin.subsystem,
            category: begin.category,
            pid: begin.pid,
            signpostID: begin.signpostID ?? 0,
            start: begin.timestamp,
            end: end.timestamp,
            durationMs: durationMs,
            message: begin.message
        )
    }

    /// Median of a pre-sorted array (linear interpolation for even counts).
    private static func median(of sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
