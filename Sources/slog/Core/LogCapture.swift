//
//  LogCapture.swift
//  slog
//

import Foundation
import Synchronization

/// Runs a live log stream until a stop condition fires. Shared by `slog stream`
/// and the MCP live tools so bounded capture has one implementation.
enum LogCapture {
    struct Limits: Sendable {
        /// Stop after this many matching entries.
        var count: Int?
        /// Stop this long after starting, whatever has arrived.
        var timeout: Duration?
        /// Stop if no matching entry arrives within this long.
        var firstEntryTimeout: Duration?
        /// Stop this long after the first matching entry.
        var captureWindow: Duration?
    }

    enum StopReason: Sendable {
        case count
        case timeout
        case firstEntryTimeout
        case captureComplete
        /// The stream ended on its own.
        case exhausted
        case error(any Error)
    }

    /// Feeds each entry matching `filter` into `ingest` until a limit is hit or
    /// the stream ends, then returns the final state and why capture stopped.
    static func run<State: Sendable>(
        _ entries: AsyncThrowingStream<LogEntry, Error>,
        filter: FilterChain = FilterChain(),
        limits: Limits,
        into initial: State,
        _ ingest: @escaping @Sendable (inout State, LogEntry) -> Void
    ) async -> (state: State, stop: StopReason) {
        let status = CaptureStatus()
        let firstEntry = AsyncStream<Void>.makeStream()

        let worker = Task {
            var state = initial
            var matched = 0
            do {
                for try await entry in entries where filter.matches(entry) {
                    if Task.isCancelled {
                        break
                    }
                    ingest(&state, entry)
                    matched += 1
                    if matched == 1 {
                        status.markFirstEntry()
                        firstEntry.continuation.finish()
                    }
                    if let max = limits.count, matched >= max {
                        _ = status.stop(.count)
                        break
                    }
                }
                _ = status.stop(.exhausted)
            } catch is CancellationError {
                _ = status.stop(.exhausted)
            } catch {
                _ = status.stop(.error(error))
            }
            firstEntry.continuation.finish()
            return state
        }

        @Sendable func stopWorker(_ reason: StopReason) {
            if status.stop(reason) {
                worker.cancel()
            }
        }

        var timers: [Task<Void, Error>] = []
        if let timeout = limits.timeout {
            timers.append(Task {
                try await Task.sleep(for: timeout)
                stopWorker(.timeout)
            })
        }
        if let firstEntryTimeout = limits.firstEntryTimeout {
            timers.append(Task {
                try await Task.sleep(for: firstEntryTimeout)
                if !status.sawFirstEntry {
                    stopWorker(.firstEntryTimeout)
                }
            })
        }
        if let captureWindow = limits.captureWindow {
            timers.append(Task {
                for await _ in firstEntry.stream {}
                guard status.sawFirstEntry else { return }
                try await Task.sleep(for: captureWindow)
                stopWorker(.captureComplete)
            })
        }

        let state = await worker.value
        timers.forEach { $0.cancel() }
        return (state, status.reason ?? .exhausted)
    }
}

/// Stop reason and first-entry flag shared between the capture worker and its timers.
private final class CaptureStatus: Sendable {
    private let state = Mutex<(reason: LogCapture.StopReason?, sawFirstEntry: Bool)>((nil, false))

    var reason: LogCapture.StopReason? {
        state.withLock { $0.reason }
    }

    var sawFirstEntry: Bool {
        state.withLock { $0.sawFirstEntry }
    }

    func markFirstEntry() {
        state.withLock { $0.sawFirstEntry = true }
    }

    /// Records `reason` if capture hasn't stopped yet. Returns whether it did.
    func stop(_ reason: LogCapture.StopReason) -> Bool {
        state.withLock { current in
            guard current.reason == nil else { return false }
            current.reason = reason
            return true
        }
    }
}
