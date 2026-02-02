//
//  PlainFormatter.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation

/// Plain text formatter for log entries
public struct PlainFormatter: LogFormatter {
    private let dateFormatter: DateFormatter
    private let showTimestamp: Bool
    private let showLevel: Bool
    private let showProcess: Bool
    private let showSubsystem: Bool

    public init(
        showTimestamp: Bool = true,
        showLevel: Bool = true,
        showProcess: Bool = true,
        showSubsystem: Bool = true
    ) {
        self.showTimestamp = showTimestamp
        self.showLevel = showLevel
        self.showProcess = showProcess
        self.showSubsystem = showSubsystem

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    public func format(_ entry: LogEntry) -> String {
        var components: [String] = []

        if showTimestamp {
            components.append(dateFormatter.string(from: entry.timestamp))
        }

        if showLevel {
            let levelStr = levelString(entry.level)
            components.append("[\(levelStr)]")
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

    private func levelString(_ level: LogLevel) -> String {
        switch level {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .default:
            return "DEFAULT"
        case .error:
            return "ERROR"
        case .fault:
            return "FAULT"
        }
    }
}
