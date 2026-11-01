//
//  DedupWriter.swift
//  slog
//

import Foundation
import Synchronization

/// Collapses consecutive log entries with identical messages into "message (xN)".
public final class DedupWriter: Sendable {
    /// The current run of identical messages, not yet written.
    private struct Run {
        let message: String
        let formatted: String
        var count: Int
    }

    private let formatter: any LogFormatter
    private let output: @Sendable (String) -> Void
    private let run = Mutex<Run?>(nil)

    /// - Parameter output: where finished lines go; standard output by default.
    public init(formatter: any LogFormatter, output: @escaping @Sendable (String) -> Void = { print($0) }) {
        self.formatter = formatter
        self.output = output
    }

    /// Write an entry, buffering it for potential deduplication.
    public func write(_ entry: LogEntry) {
        run.withLock { run in
            if run?.message == entry.message {
                run?.count += 1
            } else {
                emit(run)
                run = Run(message: entry.message, formatted: formatter.format(entry), count: 1)
            }
        }
    }

    /// Flush any buffered output.
    public func flush() {
        run.withLock { run in
            emit(run)
            run = nil
        }
    }

    private func emit(_ run: Run?) {
        guard let run else { return }
        output(run.count > 1 ? "\(run.formatted) (x\(run.count))" : run.formatted)
    }
}
