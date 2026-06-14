//
//  PlainFormatter.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation

/// Plain text formatter for log entries
public struct PlainFormatter: LogFormatter {
    private let showTimestamp: Bool
    private let showLevel: Bool
    private let showProcess: Bool
    private let showSubsystem: Bool
    private let timestampFormatter: TimestampFormatter

    public init(
        showTimestamp: Bool = true,
        showLevel: Bool = true,
        showProcess: Bool = true,
        showSubsystem: Bool = true,
        timestampFormatter: TimestampFormatter = TimestampFormatter()
    ) {
        self.showTimestamp = showTimestamp
        self.showLevel = showLevel
        self.showProcess = showProcess
        self.showSubsystem = showSubsystem
        self.timestampFormatter = timestampFormatter
    }

    public func format(_ entry: LogEntry) -> String {
        var components: [String] = []

        if showTimestamp {
            components.append(timestampFormatter.format(entry.timestamp))
        }

        if showLevel {
            components.append("[\(entry.level.rawValue.uppercased())]")
        }

        if showProcess {
            components.append("\(entry.processName)[\(entry.pid)]")
        }

        if showSubsystem, let subsystem = entry.subsystem {
            if let category = entry.category {
                components.append("(\(subsystem):\(category))")
            } else {
                components.append("(\(subsystem))")
            }
        }

        components.append(entry.message)

        return components.joined(separator: " ")
    }
}
