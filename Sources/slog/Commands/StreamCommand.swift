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

    // MARK: - Profile

    @Option(name: .long, help: "Load settings from a saved profile")
    var profile: String?

    // MARK: - Target Options

    @Option(name: .long, help: "Filter by process name (comma-separated for multiple, e.g. Finder,Dock)")
    var process: String?

    @Option(name: .long, help: "Filter by process ID")
    var pid: Int?

    @Flag(name: .long, help: "Stream from iOS Simulator instead of host")
    var simulator = false

    @Option(name: .long, help: "Simulator UDID (auto-detects if only one booted)")
    var simulatorUDID: String?

    // MARK: - Filter Options

    @Option(
        name: .long,
        help: "Filter by subsystem (comma-separated for multiple, e.g. com.apple.network,com.apple.CFNetwork)"
    )
    var subsystem: String?

    @Option(name: .long, help: "Filter by category (comma-separated for multiple, e.g. http,dns)")
    var category: String?

    @Option(name: .long, help: "Minimum log level (debug, info, default, error, fault)")
    var level: LogLevel?

    @Option(name: .long, help: "Filter messages by regex pattern")
    var grep: String?

    @Option(name: .long, help: "Exclude messages matching regex pattern")
    var excludeGrep: String?

    // MARK: - Output Options

    @Option(name: .long, help: "Output format (plain, compact, color, json, toon)")
    var format: OutputFormat?

    @Option(name: .long, help: "Timestamp mode (absolute, relative)")
    var time: TimeMode?

    @Flag(name: .long, inversion: .prefixedNo, help: "Include info-level messages")
    var info: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Include debug-level messages")
    var debug: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Include source location info")
    var source: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Collapse consecutive identical messages")
    var dedup: Bool?

    @Flag(name: .long, help: "Report os_signpost interval durations instead of log messages")
    var signpost: Bool = false

    // MARK: - Timing Options

    @Option(name: .long, help: "Maximum wait time for first log entry (e.g., 5s, 1m)")
    var timeout: String?

    @Option(name: .long, help: "Capture duration after first log entry (e.g., 10s, 2m)")
    var capture: String?

    @Option(name: .long, help: "Number of entries to capture after first log entry")
    var count: Int?

    // MARK: - Validation

    func validate() throws {
        if let timeout {
            _ = try DurationParser.parse(timeout, optionName: "--timeout")
        }

        if let capture {
            _ = try DurationParser.parse(capture, optionName: "--capture")
        }

        if let count, count <= 0 {
            throw ValidationError("--count must be a positive integer")
        }
    }

    // MARK: - Run

    func run() async throws {
        // Load profile if specified
        let prof = try profile.map { try ProfileManager.load($0) }

        // Merge CLI args with profile (CLI wins when non-nil)
        let effectiveProcess = process ?? prof?.process
        let effectivePid = pid ?? prof?.pid
        let effectiveSubsystem = subsystem ?? prof?.subsystem
        let effectiveCategory = category ?? prof?.category
        let effectiveLevel = level ?? prof?.resolvedLevel
        let effectiveGrep = grep ?? prof?.grep
        let effectiveExcludeGrep = excludeGrep ?? prof?.excludeGrep
        let effectiveFormat = format ?? prof?.resolvedFormat ?? .color
        let effectiveInfo = info ?? prof?.info ?? false
        let effectiveDebug = debug ?? prof?.debug ?? false
        let effectiveSource = source ?? prof?.source ?? false
        let effectiveSimulator = simulator || (prof?.simulator ?? false)
        let effectiveSimulatorUDID = simulatorUDID ?? prof?.simulatorUDID
        let effectiveTime = time ?? prof?.resolvedTimeMode ?? .absolute
        let effectiveDedup = dedup ?? prof?.dedup ?? false

        // Determine output format
        let formatter = FormatterRegistry.formatter(
            for: effectiveFormat,
            highlightPattern: effectiveGrep,
            timeMode: effectiveTime
        )

        // Build predicate, filter chain, and log level inclusion
        let setup = try FilterSetup.build(
            processes: FilterSetup.splitCSV(effectiveProcess),
            pid: effectivePid,
            subsystems: FilterSetup.splitCSV(effectiveSubsystem),
            categories: FilterSetup.splitCSV(effectiveCategory),
            level: effectiveLevel,
            grep: effectiveGrep,
            excludeGrep: effectiveExcludeGrep,
            info: effectiveInfo,
            debug: effectiveDebug,
            signpost: signpost
        )

        // Determine target
        let target: StreamConfiguration.Target
        if effectiveSimulator {
            let udid = try SystemQuery.resolveSimulatorUDID(effectiveSimulatorUDID)
            target = .simulator(udid: udid)
        } else {
            target = .local
        }

        // Create configuration
        let config = StreamConfiguration(
            target: target,
            predicate: setup.predicate,
            includeInfo: setup.includeInfo,
            includeDebug: setup.includeDebug,
            includeSource: effectiveSource,
            includeSignposts: signpost
        )

        // Parse timing options
        let timeoutInterval = try timeout.map { try DurationParser.parse($0, optionName: "--timeout") }
        let captureInterval = try capture.map { try DurationParser.parse($0, optionName: "--capture") }
        let maxCount = count

        // Create dedup writer if enabled (not used in signpost mode)
        let dedupWriter = (effectiveDedup && !signpost) ? DedupWriter(formatter: formatter) : nil

        // Signpost mode aggregates begin/end events into intervals, printed once
        // the stream stops (via timeout/capture/count).
        let signpostCollector = signpost ? SignpostCollector() : nil

        // Create streamer
        let streamer = LogStreamer()
        let stream = streamer.stream(configuration: config)

        // Run with timing constraints
        let exitCode = await runStream(
            stream,
            filterChain: setup.filterChain,
            formatter: formatter,
            dedupWriter: dedupWriter,
            signpostCollector: signpostCollector,
            timeoutInterval: timeoutInterval,
            captureInterval: captureInterval,
            maxCount: maxCount
        )

        if let signpostCollector {
            let (summaries, orphanEnds) = await signpostCollector.result()
            print(SignpostFormatter.render(summaries, format: effectiveFormat, orphanEndCount: orphanEnds))
        }

        if exitCode != 0 {
            throw ExitCode(Int32(exitCode))
        }
    }

    // MARK: - Stream Processing

    private func runStream(
        _ stream: AsyncThrowingStream<LogEntry, Error>,
        filterChain: FilterChain,
        formatter: LogFormatter,
        dedupWriter: DedupWriter?,
        signpostCollector: SignpostCollector? = nil,
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

                    await state.recordEntry()

                    if let signpostCollector {
                        // Predicate already restricts to signpost events; collect
                        // for end-of-stream aggregation instead of printing.
                        await signpostCollector.ingest(entry)
                    } else if let dedupWriter {
                        dedupWriter.write(entry)
                    } else {
                        let output = formatter.format(entry)
                        print(output)
                    }

                    // Check count limit
                    if let maxCount {
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
                await state.waitForFirstEntry()

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

        // Flush any buffered dedup output
        dedupWriter?.flush()

        // Clean up
        timeoutTask?.cancel()
        captureTask?.cancel()

        // Determine exit code: timeout and error are failures, everything else succeeds.
        switch await state.stopReason {
        case .timeout, .error: return 1
        case .none, .captureComplete, .countReached: return 0
        }
    }
}

// MARK: - Signpost Collector

/// Thread-safe wrapper around `SignpostAggregator` for the streaming path,
/// where entries arrive on a separate task.
private actor SignpostCollector {
    private var aggregator = SignpostAggregator()

    func ingest(_ entry: LogEntry) {
        aggregator.ingest(entry)
    }

    func result() -> (summaries: [SignpostSummary], orphanEnds: Int) {
        (aggregator.summaries(), aggregator.orphanEndCount)
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

    private var firstEntryWaiter: CheckedContinuation<Void, Never>?

    func recordEntry() {
        let wasFirst = !hasReceivedEntry
        entryCount += 1
        hasReceivedEntry = true
        if wasFirst { resumeFirstEntryWaiter() }
    }

    func stop(reason: StopReason) {
        guard !shouldStop else { return }
        shouldStop = true
        stopReason = reason
        resumeFirstEntryWaiter()
    }

    /// Suspend until `recordEntry` or `stop` fires. Returns immediately if
    /// either has already happened — no polling, no scheduled wake-ups.
    func waitForFirstEntry() async {
        if hasReceivedEntry || shouldStop { return }
        await withCheckedContinuation { firstEntryWaiter = $0 }
    }

    private func resumeFirstEntryWaiter() {
        guard let waiter = firstEntryWaiter else { return }
        firstEntryWaiter = nil
        waiter.resume()
    }
}
