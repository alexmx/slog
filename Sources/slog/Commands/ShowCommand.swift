//
//  ShowCommand.swift
//  slog
//

import ArgumentParser
import Foundation

/// Command for querying historical/persisted logs
struct ShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Query historical logs from macOS log archive"
    )

    // MARK: - Profile

    @Option(name: .long, help: "Load settings from a saved profile")
    var profile: String?

    // MARK: - Filter Options

    @Option(name: .long, help: "Filter by process name")
    var process: String?

    @Option(name: .long, help: "Filter by process ID")
    var pid: Int?

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
    var format: OutputFormat?

    @Option(name: .long, help: "Timestamp mode (absolute, relative)")
    var time: TimeMode?

    @Flag(name: .long, inversion: .prefixedNo, help: "Include info-level messages")
    var info: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Include debug-level messages")
    var debug: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Include source location info")
    var source: Bool?

    // MARK: - Time Range Options

    @Option(name: .long, help: "Show logs from last duration or boot (e.g., 5m, 1h, boot)")
    var last: String?

    @Option(name: .long, help: "Start date (e.g., \"2024-01-15 10:30:00\")")
    var start: String?

    @Option(name: .long, help: "End date (e.g., \"2024-01-15 11:00:00\")")
    var end: String?

    // MARK: - Limit Options

    @Option(name: .long, help: "Maximum number of entries to display")
    var count: Int?

    // MARK: - Archive Path

    @Argument(help: "Path to a .logarchive file (optional)")
    var archivePath: String?

    // MARK: - Validation

    func validate() throws {
        if last == nil && start == nil && archivePath == nil {
            throw ValidationError(
                "Specify a time range with --last or --start, or provide a .logarchive path"
            )
        }

        if last != nil && (start != nil || end != nil) {
            throw ValidationError("--last cannot be combined with --start or --end")
        }

        if end != nil && start == nil && archivePath == nil {
            throw ValidationError("--end requires --start or a .logarchive path")
        }

        if let count = count, count <= 0 {
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
        let effectiveFormat = format ?? prof?.resolvedFormat ?? .color
        let effectiveInfo = info ?? prof?.info ?? false
        let effectiveDebug = debug ?? prof?.debug ?? false
        let effectiveSource = source ?? prof?.source ?? false
        let effectiveTime = time ?? prof?.resolvedTimeMode ?? .absolute

        let formatter = FormatterRegistry.formatter(for: effectiveFormat, highlightPattern: effectiveGrep, timeMode: effectiveTime)

        // Build server-side predicate
        let predicate = PredicateBuilder.buildPredicate(
            process: effectiveProcess,
            pid: effectivePid,
            subsystem: effectiveSubsystem,
            category: effectiveCategory,
            level: effectiveLevel
        )

        // Build client-side filter chain for regex
        var filterChain = FilterChain()
        if let grepPattern = effectiveGrep {
            filterChain.messageRegex(grepPattern)
        }

        // Determine time range
        let timeRange: ShowConfiguration.TimeRange?
        if let last = last {
            if last.lowercased() == "boot" {
                timeRange = .lastBoot
            } else {
                timeRange = .last(last)
            }
        } else if let start = start {
            if let end = end {
                timeRange = .range(start: start, end: end)
            } else {
                timeRange = .start(start)
            }
        } else {
            timeRange = nil
        }

        // Determine log level inclusion
        let autoDebug = effectiveSubsystem != nil && effectiveLevel == nil && !effectiveInfo && !effectiveDebug
        let includeDebugLogs = effectiveDebug || autoDebug
        let includeInfoLogs = effectiveInfo || includeDebugLogs

        // Create configuration
        let config = ShowConfiguration(
            timeRange: timeRange,
            archivePath: archivePath,
            predicate: predicate,
            includeInfo: includeInfoLogs,
            includeDebug: includeDebugLogs,
            includeSource: effectiveSource
        )

        // Create reader and iterate
        let reader = LogReader()
        let stream = reader.read(configuration: config)

        var entryCount = 0
        do {
            for try await entry in stream {
                // Apply client-side filters
                guard filterChain.isEmpty || filterChain.matches(entry) else {
                    continue
                }

                let output = formatter.format(entry)
                print(output)

                entryCount += 1
                if let maxCount = count, entryCount >= maxCount {
                    break
                }
            }
        } catch is CancellationError {
            // Cancelled
        }
    }
}
