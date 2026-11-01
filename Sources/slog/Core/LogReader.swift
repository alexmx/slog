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
        /// Show logs from the last duration (e.g., "5m", "1h") or `boot`
        case last(String)
        /// Show logs starting from a specific date
        case start(Bound)
        /// Show logs in a date range
        case range(start: Bound, end: Bound)

        /// A `start`/`end` value. `log` only takes whole seconds, so a full
        /// timestamp slog can parse (ISO 8601 such as MCP's `next_since`, or a
        /// date with a zone) is kept exact and trimmed client-side; anything
        /// else (e.g. local `2024-01-15 10:30:00`) goes to `log` as written.
        public enum Bound: Sendable, Equatable {
            case exact(Date)
            case raw(String)

            public init(_ value: String) {
                self = LogTimestamp.parse(value).map(Bound.exact) ?? .raw(value)
            }

            /// The `--start`/`--end` value for `log`. An exact start is rounded
            /// down and an exact end up, so the window covers the exact bounds.
            func logArgument(roundingUp: Bool) -> String {
                switch self {
                case .exact(let date): LogTimestamp.wholeSecondArgument(date, roundingUp: roundingUp)
                case .raw(let value): value
                }
            }

            var date: Date? {
                if case .exact(let date) = self {
                    date
                } else {
                    nil
                }
            }
        }

        /// Builds a range from `last` / `start` / `end` inputs, or `nil` when
        /// neither `last` nor `start` is given. `boot` is matched case-insensitively.
        public init?(last: String?, start: String?, end: String?) {
            if let last {
                self = .last(last.lowercased() == "boot" ? "boot" : last)
            } else if let start {
                self = end.map { .range(start: Bound(start), end: Bound($0)) } ?? .start(Bound(start))
            } else {
                return nil
            }
        }

        /// Whether `date` is inside the exact bounds. `last` and raw bounds are
        /// left entirely to `log`, so they always contain it.
        func contains(_ date: Date) -> Bool {
            let (start, end): (Date?, Date?) = switch self {
            case .last: (nil, nil)
            case .start(let start): (start.date, nil)
            case .range(let start, let end): (start.date, end.date)
            }
            if let start, date < start {
                return false
            }
            if let end, date > end {
                return false
            }
            return true
        }
    }

    /// The Mac or simulator whose log store to query
    public let target: LogTarget

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

    /// Whether to surface `os_signpost` events (passes `--signpost`; they are
    /// skipped by `log show` otherwise)
    public let includeSignposts: Bool

    public init(
        target: LogTarget = .local,
        timeRange: TimeRange? = nil,
        archivePath: String? = nil,
        predicate: String? = nil,
        includeInfo: Bool = true,
        includeDebug: Bool = false,
        includeSource: Bool = false,
        includeSignposts: Bool = false
    ) {
        self.target = target
        self.timeRange = timeRange
        self.archivePath = archivePath
        self.predicate = predicate
        self.includeInfo = includeInfo
        self.includeDebug = includeDebug
        self.includeSource = includeSource
        self.includeSignposts = includeSignposts
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
        let (executable, arguments) = buildCommand(for: configuration)
        let timeRange = configuration.timeRange
        return LogProcess.entries(
            executable: executable,
            arguments: arguments,
            parser: parser,
            keep: { timeRange?.contains($0.timestamp) ?? true }
        ) {
            ShowError.logShowError($0)
        }
    }

    // MARK: - Private

    func buildCommand(for configuration: ShowConfiguration) -> (Executable, [String]) {
        configuration.target.command(buildArguments(for: configuration))
    }

    func buildArguments(for configuration: ShowConfiguration) -> [String] {
        var args = LogProcess.arguments(
            "show",
            includeInfo: configuration.includeInfo,
            includeDebug: configuration.includeDebug,
            includeSource: configuration.includeSource,
            includeSignposts: configuration.includeSignposts
        )

        // Time range arguments
        if let timeRange = configuration.timeRange {
            switch timeRange {
            case .last(let duration):
                args.append("--last")
                args.append(duration)
            case .start(let date):
                args.append("--start")
                args.append(date.logArgument(roundingUp: false))
            case .range(let start, let end):
                args.append("--start")
                args.append(start.logArgument(roundingUp: false))
                args.append("--end")
                args.append(end.logArgument(roundingUp: true))
            }
        }

        args += LogProcess.predicateArguments(configuration.predicate)

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

    public var errorDescription: String? {
        switch self {
        case .logShowError(let message):
            "Log show error: \(message)"
        }
    }
}
