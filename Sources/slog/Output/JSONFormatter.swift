//
//  JSONFormatter.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation

/// JSON output formatter for log entries
public struct JSONFormatter: LogFormatter {
    private let pretty: Bool

    public init(pretty: Bool = true) {
        self.pretty = pretty
    }

    public func format(_ entry: LogEntry) -> String {
        let output = FormattedEntry(from: entry)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if pretty {
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            } else {
                encoder.outputFormatting = [.sortedKeys]
            }
            let data = try encoder.encode(output)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            // Fallback to manual JSON construction
            return fallbackJSON(entry)
        }
    }

    private func fallbackJSON(_ entry: LogEntry) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = isoFormatter.string(from: entry.timestamp)

        let escapedMessage = entry.message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        var json = "{"
        json += "\"timestamp\":\"\(timestamp)\","
        json += "\"process\":\"\(entry.processName)\","
        json += "\"pid\":\(entry.pid),"
        json += "\"level\":\"\(entry.level.rawValue)\","
        json += "\"message\":\"\(escapedMessage)\""

        if let subsystem = entry.subsystem {
            json += ",\"subsystem\":\"\(subsystem)\""
        }

        if let category = entry.category {
            json += ",\"category\":\"\(category)\""
        }

        json += "}"
        return json
    }
}
