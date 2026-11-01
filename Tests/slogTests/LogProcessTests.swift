//
//  LogProcessTests.swift
//  slog
//

import Foundation
@testable import slog
import Subprocess
import System
import Testing

@Suite("LogProcess Tests")
struct LogProcessTests {
    private struct ExitFailure: Error {
        let message: String
    }

    /// Run `script` under `/bin/sh` and collect parsed entries plus any exit error.
    private func run(_ script: String) async -> (entries: [LogEntry], failure: String?) {
        let stream = LogProcess.entries(
            executable: .path(FilePath("/bin/sh")),
            arguments: ["-c", script],
            parser: LogParser()
        ) { ExitFailure(message: $0) }

        var entries: [LogEntry] = []
        do {
            for try await entry in stream {
                entries.append(entry)
            }
            return (entries, nil)
        } catch {
            return (entries, (error as? ExitFailure)?.message ?? "\(error)")
        }
    }

    @Test
    func stdoutLinesAreParsedAndCleanExitHasNoError() async {
        let line = #"{"timestamp":"2024-01-15T10:30:45Z","processID":7,"eventMessage":"hello"}"#
        let result = await run("echo '\(line)'; echo 'not json' >&2")

        #expect(result.entries.map(\.message) == ["hello"])
        #expect(result.failure == nil)
    }

    @Test
    func failureMessageIncludesStderr() async {
        let result = await run("echo 'first' >&2; echo 'Invalid device: BOGUS' >&2; exit 3")

        #expect(result.failure == "Process exited with code 3: first\nInvalid device: BOGUS")
    }

    @Test
    func failureWithoutStderrKeepsPlainMessage() async {
        let result = await run("exit 5")

        #expect(result.failure == "Process exited with code 5")
    }

    @Test
    func tailKeepsOnlyTheEnd() async {
        let (lines, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        for i in 1...100 {
            continuation.yield("line \(i) " + String(repeating: "x", count: 40))
        }
        continuation.finish()

        let tail = await LogProcess.tail(of: lines, limit: 200)

        #expect(tail.count <= 200)
        #expect(tail.hasSuffix("line 100 " + String(repeating: "x", count: 40)))
        #expect(!tail.contains("line 1 "))
    }

    @Test
    func tailKeepsWhatWasReadBeforeAnError() async {
        struct Boom: Error {}
        let (lines, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        continuation.yield("  partial  ")
        continuation.finish(throwing: Boom())

        #expect(await LogProcess.tail(of: lines) == "partial")
    }
}
