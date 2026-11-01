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
        do {
            let data = try TOONEncoder().encode(entry)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return JSONFormatter().format(entry)
        }
    }
}
