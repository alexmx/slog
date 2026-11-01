//
//  LogCaptureTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("LogCapture Tests")
struct LogCaptureTests {
    private func entry(pid: Int = 1, message: String = "m") -> LogEntry {
        LogEntry(
            timestamp: Date(),
            processName: "p",
            pid: pid,
            subsystem: nil,
            category: nil,
            level: .default,
            message: message
        )
    }

    /// Runs a capture that appends every entry, returning messages and the stop reason's name.
    private func capture(
        _ stream: AsyncThrowingStream<LogEntry, Error>,
        filter: FilterChain = FilterChain(),
        limits: LogCapture.Limits
    ) async -> (messages: [String], stop: String) {
        let result = await LogCapture.run(stream, filter: filter, limits: limits, into: [String]()) {
            $0.append($1.message)
        }
        return (result.state, name(of: result.stop))
    }

    private func name(of stop: LogCapture.StopReason) -> String {
        switch stop {
        case .count: "count"
        case .timeout: "timeout"
        case .firstEntryTimeout: "firstEntryTimeout"
        case .captureComplete: "captureComplete"
        case .exhausted: "exhausted"
        case .error: "error"
        }
    }

    @Test
    func stopsAtCountWithoutWaitingForStreamEnd() async {
        let (stream, continuation) = AsyncThrowingStream<LogEntry, Error>.makeStream()
        for i in 1...5 {
            continuation.yield(entry(message: "\(i)"))
        }

        let result = await capture(stream, limits: .init(count: 3))

        #expect(result.messages == ["1", "2", "3"])
        #expect(result.stop == "count")
    }

    @Test
    func endedStreamIsExhausted() async {
        let (stream, continuation) = AsyncThrowingStream<LogEntry, Error>.makeStream()
        continuation.yield(entry(message: "a"))
        continuation.finish()

        let result = await capture(stream, limits: .init(count: 10))

        #expect(result.messages == ["a"])
        #expect(result.stop == "exhausted")
    }

    @Test
    func streamFailureIsReportedWithEntriesSoFar() async {
        struct Boom: Error {}
        let (stream, continuation) = AsyncThrowingStream<LogEntry, Error>.makeStream()
        continuation.yield(entry(message: "a"))
        continuation.finish(throwing: Boom())

        let result = await capture(stream, limits: .init())

        #expect(result.messages == ["a"])
        #expect(result.stop == "error")
    }

    @Test
    func countOnlyIncludesEntriesMatchingFilter() async {
        let (stream, continuation) = AsyncThrowingStream<LogEntry, Error>.makeStream()
        continuation.yield(entry(pid: 1, message: "skip"))
        continuation.yield(entry(pid: 2, message: "keep1"))
        continuation.yield(entry(pid: 1, message: "skip"))
        continuation.yield(entry(pid: 2, message: "keep2"))
        var filter = FilterChain()
        filter.pid(2)

        let result = await capture(stream, filter: filter, limits: .init(count: 2))

        #expect(result.messages == ["keep1", "keep2"])
        #expect(result.stop == "count")
    }

    @Test
    func timeoutStopsAnOpenStream() async {
        let (stream, continuation) = AsyncThrowingStream<LogEntry, Error>.makeStream()
        continuation.yield(entry(message: "a"))

        let result = await capture(stream, limits: .init(timeout: .milliseconds(30)))

        #expect(result.messages == ["a"])
        #expect(result.stop == "timeout")
        continuation.finish()
    }

    @Test
    func firstEntryTimeoutFiresWhenNothingArrives() async {
        let (stream, continuation) = AsyncThrowingStream<LogEntry, Error>.makeStream()

        let result = await capture(stream, limits: .init(firstEntryTimeout: .milliseconds(30)))

        #expect(result.messages.isEmpty)
        #expect(result.stop == "firstEntryTimeout")
        continuation.finish()
    }

    @Test
    func firstEntryTimeoutIsDisarmedByAnEntry() async {
        let (stream, continuation) = AsyncThrowingStream<LogEntry, Error>.makeStream()
        continuation.yield(entry(message: "a"))

        let result = await capture(
            stream,
            limits: .init(timeout: .milliseconds(150), firstEntryTimeout: .milliseconds(20))
        )

        #expect(result.stop == "timeout")
        continuation.finish()
    }

    @Test
    func captureWindowStartsAtFirstEntry() async {
        let (stream, continuation) = AsyncThrowingStream<LogEntry, Error>.makeStream()
        continuation.yield(entry(message: "a"))

        let result = await capture(stream, limits: .init(captureWindow: .milliseconds(30)))

        #expect(result.messages == ["a"])
        #expect(result.stop == "captureComplete")
        continuation.finish()
    }

    @Test
    func captureWindowNeverStartsWithoutAnEntry() async {
        let (stream, continuation) = AsyncThrowingStream<LogEntry, Error>.makeStream()

        let result = await capture(
            stream,
            limits: .init(timeout: .milliseconds(80), captureWindow: .milliseconds(10))
        )

        #expect(result.stop == "timeout")
        continuation.finish()
    }
}
