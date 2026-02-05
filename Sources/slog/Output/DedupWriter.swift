//
//  DedupWriter.swift
//  slog
//

import Foundation

/// Collapses consecutive log entries with identical messages into "message (xN)".
public final class DedupWriter: @unchecked Sendable {
    private let formatter: any LogFormatter
    private var lastMessage: String?
    private var lastFormatted: String?
    private var repeatCount = 0

    public init(formatter: any LogFormatter) {
        self.formatter = formatter
    }

    /// Write an entry, buffering it for potential deduplication.
    public func write(_ entry: LogEntry) {
        let currentMessage = entry.message
        if currentMessage == lastMessage {
            repeatCount += 1
        } else {
            flush()
            lastMessage = currentMessage
            lastFormatted = formatter.format(entry)
            repeatCount = 1
        }
    }

    /// Flush any buffered output.
    public func flush() {
        guard let output = lastFormatted else { return }
        if repeatCount > 1 {
            print("\(output) (x\(repeatCount))")
        } else {
            print(output)
        }
        lastMessage = nil
        lastFormatted = nil
        repeatCount = 0
    }
}
