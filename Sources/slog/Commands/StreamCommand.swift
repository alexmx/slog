//
//  StreamCommand.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import ArgumentParser
import Foundation

/// Command for streaming logs
struct StreamCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stream",
        abstract: "Stream logs from macOS or iOS Simulator"
    )

    // MARK: - Target Options

    @Option(name: .long, help: "Filter by process name")
    var process: String?

    @Option(name: .long, help: "Filter by process ID")
    var pid: Int?

    @Flag(name: .long, help: "Stream from iOS Simulator instead of host")
    var simulator = false

    @Option(name: .long, help: "Simulator UDID (auto-detects if only one booted)")
    var simulatorUDID: String?

    // MARK: - Filter Options

    @Option(name: .long, help: "Filter by subsystem (e.g., com.apple.network)")
    var subsystem: String?

    @Option(name: .long, help: "Filter by category")
    var category: String?

    @Option(name: .long, help: "Minimum log level (debug, info, default, error, fault)")
    var level: LogLevel?

    @Option(name: .long, help: "Filter messages by regex pattern")
    var grep: String?

    // MARK: - Output Options

    @Option(name: .long, help: "Output format (plain, compact, color, json, toon)")
    var format: OutputFormat = .color

    @Flag(name: .long, help: "Include info-level messages")
    var info = false

    @Flag(name: .long, help: "Include debug-level messages")
    var debug = false

    @Flag(name: .long, help: "Include source location (file, function, line) in log entries")
    var source = false

    // MARK: - Timing Options

    @Option(name: .long, help: "Maximum wait time for first log entry (e.g., 5s, 1m)")
    var timeout: String?

    @Option(name: .long, help: "Capture duration after first log entry (e.g., 10s, 2m)")
    var capture: String?

    @Option(name: .long, help: "Number of entries to capture after first log entry")
    var count: Int?

    // MARK: - Validation

    func validate() throws {
        if let timeout = timeout {
            _ = try DurationParser.parse(timeout, optionName: "--timeout")
        }

        if let capture = capture {
            _ = try DurationParser.parse(capture, optionName: "--capture")
        }

        if let count = count, count <= 0 {
            throw ValidationError("--count must be a positive integer")
        }
    }

    // MARK: - Run

    func run() async throws {
        // Determine output format
        let formatter = FormatterRegistry.formatter(for: format)

        // Build server-side predicate
        let predicate = PredicateBuilder.buildPredicate(
            process: process,
            pid: pid,
            subsystem: subsystem,
            category: category,
            level: level
        )

        // Build client-side filter chain for regex
        var filterChain = FilterChain()
        if let grepPattern = grep {
            filterChain.messageRegex(grepPattern)
        }

        // Determine target
        let target: StreamConfiguration.Target
        if simulator {
            let udid = try resolveSimulatorUDID()
            target = .simulator(udid: udid)
        } else {
            target = .local
        }

        // Determine log level inclusion
        // Auto-enable debug when filtering by subsystem (unless explicit level set)
        let autoDebug = subsystem != nil && level == nil && !info && !debug
        let includeDebugLogs = debug || autoDebug
        let includeInfoLogs = info || includeDebugLogs

        // Create configuration
        let config = StreamConfiguration(
            target: target,
            predicate: predicate,
            includeInfo: includeInfoLogs,
            includeDebug: includeDebugLogs,
            includeSource: source
        )

        // Parse timing options
        let timeoutInterval = try timeout.map { try DurationParser.parse($0, optionName: "--timeout") }
        let captureInterval = try capture.map { try DurationParser.parse($0, optionName: "--capture") }
        let maxCount = count

        // Create streamer
        let streamer = LogStreamer()
        let stream = streamer.stream(configuration: config)

        // Run with timing constraints
        let exitCode = await runStream(
            stream,
            filterChain: filterChain,
            formatter: formatter,
            timeoutInterval: timeoutInterval,
            captureInterval: captureInterval,
            maxCount: maxCount
        )

        if exitCode != 0 {
            throw ExitCode(Int32(exitCode))
        }
    }

    // MARK: - Stream Processing

    private func runStream(
        _ stream: AsyncThrowingStream<LogEntry, Error>,
        filterChain: FilterChain,
        formatter: LogFormatter,
        timeoutInterval: TimeInterval?,
        captureInterval: TimeInterval?,
        maxCount: Int?
    ) async -> Int {
        // Use actor for thread-safe state
        let state = StreamState()

        // Wrap stream iteration in a task so we can cancel it
        let streamTask = Task {
            do {
                for try await entry in stream {
                    // Check if we should stop
                    if await state.shouldStop {
                        break
                    }

                    // Apply client-side filters
                    guard filterChain.isEmpty || filterChain.matches(entry) else {
                        continue
                    }

                    // Handle first entry - notify state
                    let isFirst = await state.recordEntry()
                    if isFirst {
                        // First entry received
                    }

                    // Output the entry
                    let output = formatter.format(entry)
                    print(output)

                    // Check count limit
                    if let maxCount = maxCount {
                        let currentCount = await state.entryCount
                        if currentCount >= maxCount {
                            await state.stop(reason: .countReached)
                            break
                        }
                    }
                }
            } catch is CancellationError {
                // Task was cancelled
            } catch {
                await state.stop(reason: .error(error))
            }
        }

        // Set up timeout task if specified
        let timeoutTask: Task<Void, Never>? = timeoutInterval.map { interval in
            Task {
                try? await Task.sleep(for: .seconds(interval))
                // If we get here without cancellation, timeout occurred
                let hasEntry = await state.hasReceivedEntry
                if !hasEntry {
                    await state.stop(reason: .timeout)
                    streamTask.cancel()
                }
            }
        }

        // Set up capture duration monitoring
        let captureTask: Task<Void, Never>? = captureInterval.map { interval in
            Task {
                // Wait for first entry
                while true {
                    let hasEntry = await state.hasReceivedEntry
                    let stopped = await state.shouldStop
                    if hasEntry || stopped { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }

                // Cancel timeout since we got first entry
                timeoutTask?.cancel()

                // Now wait for capture duration
                try? await Task.sleep(for: .seconds(interval))

                // Capture period ended
                if await !state.shouldStop {
                    await state.stop(reason: .captureComplete)
                    streamTask.cancel()
                }
            }
        }

        // Wait for stream task to complete
        await streamTask.value

        // Clean up
        timeoutTask?.cancel()
        captureTask?.cancel()

        // Determine exit code
        let reason = await state.stopReason
        switch reason {
        case .timeout:
            return 1
        case .error:
            return 1
        default:
            return 0
        }
    }

    // MARK: - Helpers

    private func resolveSimulatorUDID() throws -> String {
        if let udid = simulatorUDID {
            return udid
        }

        // Auto-detect booted simulator
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "booted", "-j"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else {
            throw StreamError.simulatorNotFound("Could not parse simulator list")
        }

        // Find first booted device
        for (_, deviceList) in devices {
            for device in deviceList {
                if let state = device["state"] as? String, state == "Booted",
                   let udid = device["udid"] as? String {
                    return udid
                }
            }
        }

        throw StreamError.simulatorNotFound("No booted simulator found. Boot a simulator or specify --simulator-udid")
    }
}

// MARK: - Stream State

private actor StreamState {
    enum StopReason {
        case none
        case timeout
        case captureComplete
        case countReached
        case error(Error)
    }

    private(set) var entryCount = 0
    private(set) var hasReceivedEntry = false
    private(set) var shouldStop = false
    private(set) var stopReason: StopReason = .none

    /// Record an entry and return true if this is the first entry
    func recordEntry() -> Bool {
        entryCount += 1
        let isFirst = !hasReceivedEntry
        hasReceivedEntry = true
        return isFirst
    }

    func stop(reason: StopReason) {
        guard !shouldStop else { return }
        shouldStop = true
        stopReason = reason
    }
}

