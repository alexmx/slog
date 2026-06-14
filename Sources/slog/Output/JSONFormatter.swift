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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]

        let data = (try? encoder.encode(FormattedEntry(from: entry))) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
