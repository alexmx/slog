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

    @OptionGroup(title: "Filter Options")
    var filter: FilterOptions

    @OptionGroup(title: "Output Options")
    var output: OutputOptions

    @OptionGroup(title: "Simulator Options")
    var simulatorOptions: SimulatorOptions

    @Flag(name: .long, help: "Report os_signpost interval durations instead of log messages")
    var signpost: Bool = false

    // MARK: - Time Range Options

    @Option(name: .long, help: "Show logs from last duration or boot (e.g., 5m, 1h, boot)")
    var last: String?

    @Option(name: .long, help: "Start date (e.g., \"2024-01-15 10:30:00\")")
    var start: String?

    @Option(name: .long, help: "End date (e.g., \"2024-01-15 11:00:00\")")
    var end: String?

    // MARK: - Limit Options

    @Option(name: .long, help: "Maximum number of entries to display")
    var limit: Int?

    // MARK: - Archive Path

    @Argument(help: "Path to a .logarchive file (optional)")
    var archivePath: String?

    // MARK: - Validation

    func validate() throws {
        if last == nil, start == nil, archivePath == nil {
            throw ValidationError(
                "Specify a time range with --last or --start, or provide a .logarchive path"
            )
        }

        if last != nil, start != nil || end != nil {
            throw ValidationError("--last cannot be combined with --start or --end")
        }

        if end != nil, start == nil, archivePath == nil {
            throw ValidationError("--end requires --start or a .logarchive path")
        }

        if let limit, limit <= 0 {
            throw ValidationError("--limit must be a positive integer")
        }
    }

    // MARK: - Run

    func run() async throws {
        let options = try ResolvedOptions(
            filter: filter,
            output: output,
            simulator: simulatorOptions.request,
            profileName: profile
        )
        if archivePath != nil, options.simulator.isRequested {
            throw ValidationError("--simulator can't be combined with a .logarchive path")
        }
        let formatter = options.formatter()
        let dedupWriter = options.dedup ? DedupWriter(formatter: formatter) : nil
        let setup = try options.filterSetup(signpost: signpost)

        let config = try await ShowConfiguration(
            target: options.target(),
            timeRange: ShowConfiguration.TimeRange(last: last, start: start, end: end),
            archivePath: archivePath,
            predicate: setup.predicate,
            includeInfo: setup.includeInfo,
            includeDebug: setup.includeDebug,
            includeSource: options.source,
            includeSignposts: signpost
        )

        // Create reader and iterate
        let reader = LogReader()
        let stream = reader.read(configuration: config)

        // Signpost mode: aggregate begin/end events into interval durations.
        if signpost {
            try await runSignpost(stream: stream, format: options.format)
            return
        }

        var entryCount = 0
        do {
            for try await entry in stream {
                // Apply client-side filters
                guard setup.filterChain.matches(entry) else {
                    continue
                }

                if let dedupWriter {
                    dedupWriter.write(entry)
                } else {
                    let output = formatter.format(entry)
                    print(output)
                }

                entryCount += 1
                if let limit, entryCount >= limit {
                    break
                }
            }
        } catch is CancellationError {
            // Cancelled
        }

        // Flush any buffered dedup output
        dedupWriter?.flush()
    }

    /// Drain the stream into a SignpostAggregator and print the interval table.
    /// The server-side predicate already restricts to signpost events, so every
    /// entry is ingested directly.
    private func runSignpost(
        stream: AsyncThrowingStream<LogEntry, Error>,
        format: OutputFormat
    ) async throws {
        var aggregator = SignpostAggregator()
        do {
            for try await entry in stream {
                aggregator.ingest(entry)
            }
        } catch is CancellationError {
            // Cancelled — render whatever was collected.
        }

        let output = SignpostFormatter.render(
            aggregator.summaries(),
            format: format,
            orphanEndCount: aggregator.orphanEndCount
        )
        print(output)
    }
}
