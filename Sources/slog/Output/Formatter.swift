//
//  Formatter.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import ArgumentParser
import Foundation
import Synchronization

/// Timestamp display mode
public enum TimeMode: String, CaseIterable, Sendable, ExpressibleByArgument {
    case absolute
    case relative
}

/// Formats timestamps. In relative mode each call shows the gap since the
/// previous call, so one instance should format one stream in order.
public final class TimestampFormatter: Sendable {
    private let mode: TimeMode
    private let dateFormatter: DateFormatter
    private let previousTimestamp = Mutex<Date?>(nil)

    public init(mode: TimeMode = .absolute) {
        self.mode = mode
        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    public func format(_ timestamp: Date) -> String {
        switch mode {
        case .absolute:
            return dateFormatter.string(from: timestamp)
        case .relative:
            let previous = previousTimestamp.withLock { previous in
                defer { previous = timestamp }
                return previous
            }
            guard let previous else {
                return "+0.000s"
            }
            return formatDelta(timestamp.timeIntervalSince(previous))
        }
    }

    private func formatDelta(_ delta: TimeInterval) -> String {
        let absDelta = abs(delta)
        let sign = delta < 0 ? "-" : "+"
        if absDelta < 60 {
            return String(format: "%@%.3fs", sign, absDelta)
        } else if absDelta < 3600 {
            let minutes = Int(absDelta) / 60
            let seconds = absDelta - Double(minutes * 60)
            return String(format: "%@%dm%05.2fs", sign, minutes, seconds)
        } else {
            let hours = Int(absDelta) / 3600
            let minutes = (Int(absDelta) % 3600) / 60
            return String(format: "%@%dh%02dm", sign, hours, minutes)
        }
    }
}

/// Output format options
public enum OutputFormat: String, CaseIterable, Sendable, CustomStringConvertible, ExpressibleByArgument {
    case plain
    case compact
    case color
    case json
    case toon

    public var description: String {
        switch self {
        case .plain:
            "Plain text output"
        case .compact:
            "Compact output (timestamp, level, message only)"
        case .color:
            "Colored output based on log level"
        case .json:
            "JSON output for piping to other tools"
        case .toon:
            "TOON output (token-optimized for LLMs)"
        }
    }
}

/// Protocol for formatting log entries for output
public protocol LogFormatter: Sendable {
    /// Format a log entry for display
    func format(_ entry: LogEntry) -> String
}

/// Registry for available formatters
public enum FormatterRegistry {
    public static func formatter(
        for format: OutputFormat,
        highlightPattern: String? = nil,
        timeMode: TimeMode = .absolute
    ) -> any LogFormatter {
        let timestampFormatter = TimestampFormatter(mode: timeMode)
        switch format {
        case .plain:
            return PlainFormatter(timestampFormatter: timestampFormatter)
        case .compact:
            return ColorFormatter(
                showProcess: false,
                showSubsystem: false,
                highlightPattern: highlightPattern,
                timestampFormatter: timestampFormatter
            )
        case .color:
            return ColorFormatter(
                highlightPattern: highlightPattern,
                timestampFormatter: timestampFormatter
            )
        case .json:
            return JSONFormatter()
        case .toon:
            return ToonFormatter()
        }
    }
}
