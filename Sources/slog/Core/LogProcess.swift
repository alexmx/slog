//
//  LogProcess.swift
//  slog
//

import Foundation
import Subprocess

/// Runs a `log` subcommand and streams its NDJSON output as parsed entries.
/// Shared by `LogReader` (`log show`) and `LogStreamer` (`log stream`).
enum LogProcess {
    /// The subcommand plus the output/level flags every `log show`/`log stream` call shares.
    static func arguments(
        _ subcommand: String,
        includeInfo: Bool,
        includeDebug: Bool,
        includeSource: Bool,
        includeSignposts: Bool
    ) -> [String] {
        var args = [subcommand, "--style", "ndjson"]
        if includeInfo {
            args.append("--info")
        }
        if includeDebug {
            args.append("--debug")
        }
        if includeSource {
            args.append("--source")
        }
        if includeSignposts {
            args.append("--signpost")
        }
        return args
    }

    static func predicateArguments(_ predicate: String?) -> [String] {
        predicate.map { ["--predicate", $0] } ?? []
    }

    /// Launches the process and yields each parsed line. Cancelling the stream
    /// tears the process down; a non-zero exit finishes it with `exitError`,
    /// whose message ends with the process's last stderr output.
    static func entries(
        executable: Executable,
        arguments: [String],
        parser: LogParser,
        exitError: @escaping @Sendable (String) -> any Error
    ) -> AsyncThrowingStream<LogEntry, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await run(
                        executable,
                        arguments: Arguments(arguments),
                        input: .none,
                        output: .sequence,
                        error: .sequence
                    ) { execution in
                        // Drain stderr alongside stdout so it can't block the
                        // process, keeping its tail for the failure message.
                        let standardError = execution.standardError.strings()
                        async let errorTail = tail(of: standardError)
                        for try await line in execution.standardOutput.strings() {
                            if Task.isCancelled {
                                break
                            }
                            if let entry = parser.parse(line: line) {
                                continuation.yield(entry)
                            }
                        }
                        return await errorTail
                    }

                    if case .exited(let code) = result.terminationStatus, code != 0 {
                        let detail = result.closureResult
                        let message = "Process exited with code \(code)" + (detail.isEmpty ? "" : ": \(detail)")
                        continuation.finish(throwing: exitError(message))
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

    /// The last lines of `lines`, at most about `limit` characters, trimmed.
    /// A read error (including cancellation) ends collection with what was read.
    static func tail(of lines: some AsyncSequence<String, any Error>, limit: Int = 2048) async -> String {
        var kept: [String] = []
        var length = 0
        do {
            for try await line in lines {
                kept.append(line)
                length += line.count + 1
                while length > limit, kept.count > 1 {
                    length -= kept.removeFirst().count + 1
                }
            }
        } catch {
            // Keep what was read.
        }
        let text = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > limit ? String(text.suffix(limit)) : text
    }
}
