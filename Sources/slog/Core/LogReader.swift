//
//  LogReader.swift
//  slog
//

import Foundation
import Subprocess
import System

/// Configuration for querying historical logs via `log show`
public struct ShowConfiguration: Sendable, Equatable {
    /// Time range for the log query
    public enum TimeRange: Sendable, Equatable {
        /// Show logs from the last N seconds/minutes/hours (e.g., "5m", "1h")
        case last(String)
        /// Show logs from the last boot
        case lastBoot
        /// Show logs starting from a specific date
        case start(String)
        /// Show logs in a date range
        case range(start: String, end: String)
    }

    /// The time range to query
    public let timeRange: TimeRange?

    /// Optional path to a .logarchive file
    public let archivePath: String?

    /// Server-side predicate for filtering
    public let predicate: String?

    /// Whether to include info-level messages
    public let includeInfo: Bool

    /// Whether to include debug-level messages
    public let includeDebug: Bool

    /// Whether to include source location info
    public let includeSource: Bool

    public init(
        timeRange: TimeRange? = nil,
        archivePath: String? = nil,
        predicate: String? = nil,
        includeInfo: Bool = true,
        includeDebug: Bool = false,
        includeSource: Bool = false
    ) {
        self.timeRange = timeRange
        self.archivePath = archivePath
        self.predicate = predicate
        self.includeInfo = includeInfo
        self.includeDebug = includeDebug
        self.includeSource = includeSource
    }
}

/// Reads historical logs using `log show`
public struct LogReader: Sendable {
    private let parser: LogParser

    public init(parser: LogParser = LogParser()) {
        self.parser = parser
    }

    /// Read log entries asynchronously
    public func read(
        configuration: ShowConfiguration
    ) -> AsyncThrowingStream<LogEntry, Error> {
        let parser = self.parser
        let arguments = buildArguments(for: configuration)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await run(
                        .path(FilePath("/usr/bin/log")),
                        arguments: Arguments(arguments)
                    ) { execution, stdout in
                        for try await line in stdout.lines() {
                            if Task.isCancelled { break }
                            if let entry = parser.parse(line: line) {
                                continuation.yield(entry)
                            }
                        }
                    }

                    if case .exited(let code) = result.terminationStatus, code != 0 {
                        continuation.finish(throwing: ShowError.logShowError("Process exited with code \(code)"))
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

    func buildArguments(for configuration: ShowConfiguration) -> [String] {
        var args = ["show", "--style", "ndjson"]

        if configuration.includeInfo {
            args.append("--info")
        }

        if configuration.includeDebug {
            args.append("--debug")
        }

        if configuration.includeSource {
            args.append("--source")
        }

        // Time range arguments
        if let timeRange = configuration.timeRange {
            switch timeRange {
            case .last(let duration):
                args.append("--last")
                args.append(duration)
            case .lastBoot:
                args.append("--last")
                args.append("boot")
            case .start(let date):
                args.append("--start")
                args.append(date)
            case .range(let start, let end):
                args.append("--start")
                args.append(start)
                args.append("--end")
                args.append(end)
            }
        }

        if let predicate = configuration.predicate {
            args.append("--predicate")
            args.append(predicate)
        }

        // Archive path goes last as a positional argument
        if let archivePath = configuration.archivePath {
            args.append(archivePath)
        }

        return args
    }
}

// MARK: - Errors

public enum ShowError: Error, LocalizedError {
    case logShowError(String)
    case invalidTimeRange(String)

    public var errorDescription: String? {
        switch self {
        case .logShowError(let message):
            return "Log show error: \(message)"
        case .invalidTimeRange(let message):
            return "Invalid time range: \(message)"
        }
    }
}
