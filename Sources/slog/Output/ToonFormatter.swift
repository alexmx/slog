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
        let output = ToonOutput(from: entry)

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
            "message: \(entry.message)",
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

// MARK: - TOON Output Model

private struct ToonOutput: Encodable {
    let timestamp: Date
    let process: String
    let pid: Int
    let level: String
    let message: String
    let subsystem: String?
    let category: String?
    let threadID: Int?
    let activityID: Int?
    let processImagePath: String?
    let senderImagePath: String?
    let eventType: String?
    let source: String?

    init(from entry: LogEntry) {
        timestamp = entry.timestamp
        process = entry.processName
        pid = entry.pid
        level = entry.level.rawValue
        message = entry.message
        subsystem = entry.subsystem
        category = entry.category
        threadID = entry.threadID
        activityID = entry.activityID
        processImagePath = entry.processImagePath
        senderImagePath = entry.senderImagePath
        eventType = entry.eventType
        source = entry.source
    }
}
