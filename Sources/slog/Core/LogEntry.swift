//
//  LogEntry.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation

/// Represents the severity level of a log entry
public enum LogLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case `default` = "Default"
    case info = "Info"
    case debug = "Debug"
    case error = "Error"
    case fault = "Fault"

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .default, .error, .fault]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }

    /// Parse from various string representations
    public init?(string: String) {
        let lowercased = string.lowercased()
        switch lowercased {
        case "default":
            self = .default
        case "info":
            self = .info
        case "debug":
            self = .debug
        case "error":
            self = .error
        case "fault":
            self = .fault
        default:
            return nil
        }
    }
}

/// Represents a single parsed log entry from the log stream
public struct LogEntry: Codable, Sendable {
    /// Timestamp of the log entry
    public let timestamp: Date

    /// Process name that generated the log
    public let processName: String

    /// Process ID
    public let pid: Int

    /// Subsystem identifier (e.g., "com.apple.network")
    public let subsystem: String?

    /// Category within the subsystem
    public let category: String?

    /// Log level/type
    public let level: LogLevel

    /// The actual log message
    public let message: String

    /// Thread ID that generated the log
    public let threadID: Int?

    /// Activity ID if available
    public let activityID: Int?

    /// Trace ID if available
    public let traceID: Int?

    public init(
        timestamp: Date,
        processName: String,
        pid: Int,
        subsystem: String?,
        category: String?,
        level: LogLevel,
        message: String,
        threadID: Int? = nil,
        activityID: Int? = nil,
        traceID: Int? = nil
    ) {
        self.timestamp = timestamp
        self.processName = processName
        self.pid = pid
        self.subsystem = subsystem
        self.category = category
        self.level = level
        self.message = message
        self.threadID = threadID
        self.activityID = activityID
        self.traceID = traceID
    }
}

extension LogEntry: CustomStringConvertible {
    public var description: String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timeString = dateFormatter.string(from: timestamp)

        var components = [timeString, "[\(level.rawValue)]", processName, "(\(pid))"]

        if let subsystem = subsystem {
            components.append("[\(subsystem)]")
        }

        if let category = category {
            components.append("[\(category)]")
        }

        components.append(message)

        return components.joined(separator: " ")
    }
}
