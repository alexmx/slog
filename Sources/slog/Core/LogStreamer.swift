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
    /// Target for log streaming
    public enum Target: Sendable, Equatable {
        /// Stream from the local macOS system
        case local
        /// Stream from an iOS Simulator with the given UDID
        case simulator(udid: String)
    }

    /// The target to stream logs from
    public let target: Target

    /// Server-side predicate for filtering (passed to `log stream --predicate`)
    public let predicate: String?

    /// Whether to include info-level messages
    public let includeInfo: Bool

    /// Whether to include debug-level messages
    public let includeDebug: Bool

    /// Whether to include source location info
    public let includeSource: Bool

    public init(
        target: Target = .local,
        predicate: String? = nil,
        includeInfo: Bool = true,
        includeDebug: Bool = false,
        includeSource: Bool = false
    ) {
        self.target = target
        self.predicate = predicate
        self.includeInfo = includeInfo
        self.includeDebug = includeDebug
        self.includeSource = includeSource
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
        let parser = parser
        let (executable, arguments) = buildCommand(for: configuration)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await run(
                        executable,
                        arguments: Arguments(arguments)
                    ) { _, stdout in
                        for try await line in stdout.lines() {
                            if Task.isCancelled { break }
                            if let entry = parser.parse(line: line) {
                                continuation.yield(entry)
                            }
                        }
                    }

                    // Check termination status
                    if case .exited(let code) = result.terminationStatus, code != 0 {
                        continuation.finish(throwing: StreamError.logStreamError("Process exited with code \(code)"))
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private

    func buildCommand(for configuration: StreamConfiguration) -> (Executable, [String]) {
        var args = ["stream", "--style", "ndjson"]

        if configuration.includeInfo {
            args.append("--info")
        }

        if configuration.includeDebug {
            args.append("--debug")
        }

        if configuration.includeSource {
            args.append("--source")
        }

        if let predicate = configuration.predicate {
            args.append("--predicate")
            args.append(predicate)
        }

        switch configuration.target {
        case .local:
            return (.path(FilePath("/usr/bin/log")), args)

        case .simulator(let udid):
            let simctlArgs = ["simctl", "spawn", udid, "log"] + args
            return (.path(FilePath("/usr/bin/xcrun")), simctlArgs)
        }
    }
}

// MARK: - Errors

public enum StreamError: Error, LocalizedError {
    case logStreamError(String)
    case simulatorNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .logStreamError(let message):
            "Log stream error: \(message)"
        case .simulatorNotFound(let udid):
            "Simulator not found: \(udid)"
        }
    }
}

// MARK: - Predicate Builder

/// Builds predicates for the `log stream --predicate` option
public struct PredicateBuilder: Sendable {
    private var components: [String] = []

    public init() {}

    /// Filter by process name
    public mutating func process(_ name: String) {
        components.append("processImagePath ENDSWITH \"/\(name)\"")
    }

    /// Filter by process ID
    public mutating func pid(_ pid: Int) {
        components.append("processID == \(pid)")
    }

    /// Filter by subsystem (uses BEGINSWITH to include child subsystems)
    public mutating func subsystem(_ subsystem: String) {
        components.append("subsystem BEGINSWITH \"\(subsystem)\"")
    }

    /// Filter by category
    public mutating func category(_ category: String) {
        components.append("category == \"\(category)\"")
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

    /// Filter by message content (contains)
    public mutating func messageContains(_ text: String) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        components.append("eventMessage CONTAINS \"\(escaped)\"")
    }

    /// Build the final predicate string
    public func build() -> String? {
        guard !components.isEmpty else { return nil }
        return components.joined(separator: " AND ")
    }

    /// Create a predicate string from common filter options
    public static func buildPredicate(
        process: String? = nil,
        pid: Int? = nil,
        subsystem: String? = nil,
        category: String? = nil,
        level: LogLevel? = nil
    ) -> String? {
        var builder = PredicateBuilder()

        if let process {
            builder.process(process)
        }
        if let pid {
            builder.pid(pid)
        }
        if let subsystem {
            builder.subsystem(subsystem)
        }
        if let category {
            builder.category(category)
        }
        if let level {
            builder.level(level)
        }

        return builder.build()
    }
}
