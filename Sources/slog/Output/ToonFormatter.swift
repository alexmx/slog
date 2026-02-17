//
//  ToonFormatter.swift
//  slog
//

import Foundation
import ToonFormat

/// TOON output formatter for log entries
public struct ToonFormatter: LogFormatter {
    public init() {}

    public func format(_ entry: LogEntry) -> String {
        let output = FormattedEntry(from: entry)

        do {
            let encoder = TOONEncoder()
            let data = try encoder.encode(output)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return fallbackFormat(entry)
        }
    }

    private func fallbackFormat(_ entry: LogEntry) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = isoFormatter.string(from: entry.timestamp)

        var lines = [
            "timestamp: \(timestamp)",
            "process: \(entry.processName)",
            "pid: \(entry.pid)",
            "level: \(entry.level.rawValue)",
            "message: \(entry.message)"
        ]

        if let subsystem = entry.subsystem {
            lines.append("subsystem: \(subsystem)")
        }
        if let category = entry.category {
            lines.append("category: \(category)")
        }

        return lines.joined(separator: "\n")
    }
}
