//
//  LogEntry.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import ArgumentParser
import Foundation

/// Represents the severity level of a log entry.
/// Cases are declared in ascending severity order, which `Comparable` relies on.
public enum LogLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case debug = "Debug"
    case info = "Info"
    case `default` = "Default"
    case error = "Error"
    case fault = "Fault"

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        guard let lhsIndex = allCases.firstIndex(of: lhs),
              let rhsIndex = allCases.firstIndex(of: rhs)
        else {
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

extension LogLevel: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(string: argument)
    }

    public static var allValueStrings: [String] {
        ["debug", "info", "default", "error", "fault"]
    }
}

/// The kind of an `os_signpost` event, as reported by `log --signpost`.
///
/// Interval timing is reconstructed by pairing a `.begin` with the matching
/// `.end` (same process, signpost name, and signpost ID). `.event` is a
/// standalone marker, not part of an interval.
public enum SignpostType: String, Codable, CaseIterable, Sendable, Equatable {
    case begin
    case end
    case event

    /// Map a raw NDJSON `signpostType` value, tolerating unknown strings.
    public init?(string: String) {
        switch string.lowercased() {
        case "begin": self = .begin
        case "end": self = .end
        case "event": self = .event
        default: return nil
        }
    }
}

/// Represents a single parsed log entry from the log stream
public struct LogEntry: Codable, Sendable, Equatable {
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

    /// Full path to the process binary
    public let processImagePath: String?

    /// Library/framework that emitted the log
    public let senderImagePath: String?

    /// Event type (e.g., "logEvent", "activityCreateEvent", "traceEvent", "signpostEvent")
    public let eventType: String?

    /// Source location info (file/function/line when --source is used)
    public let source: String?

    /// Signpost instance identifier, present when `eventType == "signpostEvent"`.
    /// Distinguishes concurrent intervals that share the same name. `UInt64`
    /// because event-type signpost IDs can exceed `Int64`.
    public let signpostID: UInt64?

    /// Signpost name (e.g., "parse.postImage"), present for signpost events.
    public let signpostName: String?

    /// Whether this signpost event begins an interval, ends one, or is a
    /// standalone event.
    public let signpostType: SignpostType?

    /// Signpost scope (e.g., "process", "thread", "system").
    public let signpostScope: String?

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
        traceID: Int? = nil,
        processImagePath: String? = nil,
        senderImagePath: String? = nil,
        eventType: String? = nil,
        source: String? = nil,
        signpostID: UInt64? = nil,
        signpostName: String? = nil,
        signpostType: SignpostType? = nil,
        signpostScope: String? = nil
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
        self.processImagePath = processImagePath
        self.senderImagePath = senderImagePath
        self.eventType = eventType
        self.source = source
        self.signpostID = signpostID
        self.signpostName = signpostName
        self.signpostType = signpostType
        self.signpostScope = signpostScope
    }
}

extension LogEntry: CustomStringConvertible {
    public var description: String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timeString = dateFormatter.string(from: timestamp)

        var components = [timeString, "[\(level.rawValue)]", processName, "(\(pid))"]

        if let subsystem {
            components.append("[\(subsystem)]")
        }

        if let category {
            components.append("[\(category)]")
        }

        if let senderImagePath {
            let senderName = URL(fileURLWithPath: senderImagePath).lastPathComponent
            components.append("<\(senderName)>")
        }

        components.append(message)

        return components.joined(separator: " ")
    }
}
