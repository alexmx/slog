//
//  Formatter.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation

/// Output format options
public enum OutputFormat: String, CaseIterable, Sendable {
    case plain
    case color
    case json

    public var description: String {
        switch self {
        case .plain:
            return "Plain text output"
        case .color:
            return "Colored output based on log level"
        case .json:
            return "JSON output for piping to other tools"
        }
    }
}

/// Protocol for formatting log entries for output
public protocol LogFormatter: Sendable {
    /// Format a log entry for display
    func format(_ entry: LogEntry) -> String
}

/// Registry for available formatters
public struct FormatterRegistry {
    public static func formatter(for format: OutputFormat) -> any LogFormatter {
        switch format {
        case .plain:
            return PlainFormatter()
        case .color:
            return ColorFormatter()
        case .json:
            return JSONFormatter()
        }
    }
}
