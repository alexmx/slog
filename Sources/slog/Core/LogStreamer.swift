//
//  LogStreamer.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation
import Subprocess
import System

/// Configuration for log streaming
public struct StreamConfiguration: Sendable, Equatable {
    /// The Mac or simulator to stream logs from
    public let target: LogTarget

    /// Server-side predicate for filtering (passed to `log stream --predicate`)
    public let predicate: String?

    /// Whether to include info-level messages
    public let includeInfo: Bool

    /// Whether to include debug-level messages
    public let includeDebug: Bool

    /// Whether to include source location info
    public let includeSource: Bool

    /// Whether to surface `os_signpost` events (passes `--signpost`; they are
    /// not streamed otherwise)
    public let includeSignposts: Bool

    public init(
        target: LogTarget = .local,
        predicate: String? = nil,
        includeInfo: Bool = true,
        includeDebug: Bool = false,
        includeSource: Bool = false,
        includeSignposts: Bool = false
    ) {
        self.target = target
        self.predicate = predicate
        self.includeInfo = includeInfo
        self.includeDebug = includeDebug
        self.includeSource = includeSource
        self.includeSignposts = includeSignposts
    }
}

/// Manages spawning and reading from `log stream` process using swift-subprocess
public struct LogStreamer: Sendable {
    private let parser: LogParser

    public init(parser: LogParser = LogParser()) {
        self.parser = parser
    }

    /// Stream log entries asynchronously
    /// - Parameter configuration: The stream configuration
    /// - Returns: An async stream of log entries
    public func stream(
        configuration: StreamConfiguration
    ) -> AsyncThrowingStream<LogEntry, Error> {
        let (executable, arguments) = buildCommand(for: configuration)
        return LogProcess.entries(executable: executable, arguments: arguments, parser: parser) {
            StreamError.logStreamError($0)
        }
    }

    // MARK: - Private

    func buildCommand(for configuration: StreamConfiguration) -> (Executable, [String]) {
        let args = LogProcess.arguments(
            "stream",
            includeInfo: configuration.includeInfo,
            includeDebug: configuration.includeDebug,
            includeSource: configuration.includeSource,
            includeSignposts: configuration.includeSignposts
        ) + LogProcess.predicateArguments(configuration.predicate)
        return configuration.target.command(args)
    }
}

// MARK: - Errors

public enum StreamError: Error, LocalizedError {
    case logStreamError(String)

    public var errorDescription: String? {
        switch self {
        case .logStreamError(let message):
            "Log stream error: \(message)"
        }
    }
}

// MARK: - Predicate Builder

/// Builds predicates for the `log stream --predicate` option
public struct PredicateBuilder: Sendable {
    private var components: [String] = []

    public init() {}

    /// Filter by process name (multiple values OR-grouped)
    public mutating func processes(_ names: [String]) {
        appendOred(names.map { "processImagePath ENDSWITH \(Self.quoted("/" + $0))" })
    }

    /// Filter by process ID
    public mutating func pid(_ pid: Int) {
        components.append("processID == \(pid)")
    }

    /// Filter by subsystem (uses BEGINSWITH to include child subsystems; multiple values OR-grouped)
    public mutating func subsystems(_ values: [String]) {
        appendOred(values.map { "subsystem BEGINSWITH \(Self.quoted($0))" })
    }

    /// Filter by category (multiple values OR-grouped)
    public mutating func categories(_ values: [String]) {
        appendOred(values.map { "category == \(Self.quoted($0))" })
    }

    /// Restrict to `os_signpost` events (begin/end/event records).
    public mutating func signpostsOnly() {
        components.append("eventType == \"signpostEvent\"")
    }

    /// A double-quoted predicate string literal, with `\` and `"` escaped so
    /// the value is matched literally.
    static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private mutating func appendOred(_ parts: [String]) {
        guard !parts.isEmpty else { return }
        components.append(parts.count == 1 ? parts[0] : "(\(parts.joined(separator: " OR ")))")
    }

    /// Filter by minimum log level
    public mutating func level(_ level: LogLevel) {
        let levelValue = switch level {
        case .debug:
            0
        case .info:
            1
        case .default:
            2
        case .error:
            16
        case .fault:
            17
        }
        components.append("messageType >= \(levelValue)")
    }

    /// Build the final predicate string
    public func build() -> String? {
        guard !components.isEmpty else { return nil }
        return components.joined(separator: " AND ")
    }

    /// Create a predicate string from common filter options.
    /// `processes`, `subsystems`, and `categories` accept multiple values that are OR-grouped.
    public static func buildPredicate(
        processes: [String] = [],
        pid: Int? = nil,
        subsystems: [String] = [],
        categories: [String] = [],
        level: LogLevel? = nil,
        signpostOnly: Bool = false
    ) -> String? {
        var builder = PredicateBuilder()

        builder.processes(processes)
        if let pid {
            builder.pid(pid)
        }
        builder.subsystems(subsystems)
        builder.categories(categories)
        // Skip the messageType/level constraint in signpost mode — signpost
        // events carry a different messageType and would be filtered out.
        if let level, !signpostOnly {
            builder.level(level)
        }
        if signpostOnly {
            builder.signpostsOnly()
        }

        return builder.build()
    }
}
