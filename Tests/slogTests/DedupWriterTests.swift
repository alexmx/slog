//
//  DedupWriterTests.swift
//  slog
//

import Foundation
@testable import slog
import Synchronization
import Testing

/// Test formatter that returns just the message
private struct MessageOnlyFormatter: LogFormatter {
    func format(_ entry: LogEntry) -> String {
        entry.message
    }
}

@Suite("DedupWriter Tests")
struct DedupWriterTests {
    private func makeEntry(message: String) -> LogEntry {
        LogEntry(
            timestamp: Date(),
            processName: "Test",
            pid: 1,
            subsystem: nil,
            category: nil,
            level: .default,
            message: message
        )
    }

    @Test
    func uniqueMessages() {
        let writer = DedupWriter(formatter: MessageOnlyFormatter())

        // Redirect stdout is complex, so we test internal state via flush behavior
        // Instead, verify the writer doesn't crash with unique messages
        writer.write(makeEntry(message: "first"))
        writer.write(makeEntry(message: "second"))
        writer.write(makeEntry(message: "third"))
        writer.flush()
    }

    @Test
    func consecutiveIdentical() {
        let writer = DedupWriter(formatter: MessageOnlyFormatter())

        writer.write(makeEntry(message: "same"))
        writer.write(makeEntry(message: "same"))
        writer.write(makeEntry(message: "same"))
        // When flushed, should print "same (x3)"
        writer.flush()
    }

    @Test
    func differentAfterDuplicates() {
        let writer = DedupWriter(formatter: MessageOnlyFormatter())

        writer.write(makeEntry(message: "repeated"))
        writer.write(makeEntry(message: "repeated"))
        writer.write(makeEntry(message: "new"))
        writer.flush()
    }

    @Test
    func singleMessage() {
        let writer = DedupWriter(formatter: MessageOnlyFormatter())

        writer.write(makeEntry(message: "only"))
        writer.flush()
    }

    @Test
    func emptyFlush() {
        let writer = DedupWriter(formatter: MessageOnlyFormatter())
        writer.flush()
    }

    // MARK: - Output

    /// Collects written lines so tests can check the deduplicated output.
    private final class Lines: Sendable {
        private let storage = Mutex<[String]>([])
        var all: [String] {
            storage.withLock { $0 }
        }

        func append(_ line: String) {
            storage.withLock { $0.append(line) }
        }
    }

    private func written(_ messages: [String]) -> [String] {
        let lines = Lines()
        let writer = DedupWriter(formatter: MessageOnlyFormatter()) { lines.append($0) }
        for message in messages {
            writer.write(makeEntry(message: message))
        }
        writer.flush()
        return lines.all
    }

    @Test
    func repeatsCollapseIntoACount() {
        #expect(written(["a", "a", "a", "b", "a"]) == ["a (x3)", "b", "a"])
    }

    @Test
    func uniqueMessagesPassThrough() {
        #expect(written(["a", "b", "c"]) == ["a", "b", "c"])
    }

    @Test
    func nothingIsWrittenUntilARunEnds() {
        let lines = Lines()
        let writer = DedupWriter(formatter: MessageOnlyFormatter()) { lines.append($0) }
        writer.write(makeEntry(message: "a"))
        writer.write(makeEntry(message: "a"))
        #expect(lines.all.isEmpty)
        writer.flush()
        #expect(lines.all == ["a (x2)"])
    }

    @Test
    func flushTwiceWritesOnce() {
        let lines = Lines()
        let writer = DedupWriter(formatter: MessageOnlyFormatter()) { lines.append($0) }
        writer.write(makeEntry(message: "a"))
        writer.flush()
        writer.flush()
        #expect(lines.all == ["a"])
    }
}
