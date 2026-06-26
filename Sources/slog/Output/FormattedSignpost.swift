//
//  FormattedSignpost.swift
//  slog
//

import Foundation

/// Shared Encodable model for structured signpost output (JSON, TOON, MCP).
/// Mirrors `SignpostSummary` with snake_case keys and rounded millisecond stats.
public struct FormattedSignpost: Encodable, Sendable {
    public let name: String
    public let subsystem: String?
    public let category: String?
    public let count: Int
    public let inFlight: Int
    public let minMs: Double?
    public let p50Ms: Double?
    public let maxMs: Double?
    public let totalMs: Double?
    /// Per-occurrence detail. Omitted (nil) in aggregate-only responses.
    public let occurrences: [FormattedSignpostOccurrence]?

    enum CodingKeys: String, CodingKey {
        case name
        case subsystem
        case category
        case count
        case inFlight = "in_flight"
        case minMs = "min_ms"
        case p50Ms = "p50_ms"
        case maxMs = "max_ms"
        case totalMs = "total_ms"
        case occurrences
    }

    public init(from summary: SignpostSummary, includeOccurrences: Bool = true) {
        self.name = summary.name
        self.subsystem = summary.subsystem
        self.category = summary.category
        self.count = summary.count
        self.inFlight = summary.inFlightCount
        self.minMs = Self.round(summary.minMs)
        self.p50Ms = Self.round(summary.p50Ms)
        self.maxMs = Self.round(summary.maxMs)
        self.totalMs = Self.round(summary.totalMs)
        self.occurrences = includeOccurrences
            ? summary.occurrences.map(FormattedSignpostOccurrence.init)
            : nil
    }

    /// Round to 3 decimal places (microsecond precision) to keep JSON tidy.
    static func round(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return (value * 1000).rounded() / 1000
    }
}

/// A single interval occurrence in structured output.
public struct FormattedSignpostOccurrence: Encodable, Sendable {
    public let start: Date
    public let durationMs: Double?
    public let message: String

    enum CodingKeys: String, CodingKey {
        case start
        case durationMs = "duration_ms"
        case message
    }

    public init(_ interval: SignpostInterval) {
        self.start = interval.start
        self.durationMs = FormattedSignpost.round(interval.durationMs)
        self.message = interval.message
    }
}
