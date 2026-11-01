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

    @OptionGroup(title: "Filter Options")
    var filter: FilterOptions

    @OptionGroup(title: "Output Options")
    var output: OutputOptions

    @OptionGroup(title: "Simulator Options")
    var simulatorOptions: SimulatorOptions

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
        let options = try ResolvedOptions(
            filter: filter,
            output: output,
            simulator: simulatorOptions.request,
            profileName: profile
        )
        let formatter = options.formatter()
        let setup = try options.filterSetup(signpost: signpost)

        let config = try await StreamConfiguration(
            target: options.target(),
            predicate: setup.predicate,
            includeInfo: setup.includeInfo,
            includeDebug: setup.includeDebug,
            includeSource: options.source,
            includeSignposts: signpost
        )

        let limits = try LogCapture.Limits(
            count: count,
            firstEntryTimeout: timeout.map { try .seconds(DurationParser.parse($0, optionName: "--timeout")) },
            captureWindow: capture.map { try .seconds(DurationParser.parse($0, optionName: "--capture")) }
        )
        let stream = LogStreamer().stream(configuration: config)

        let stop: LogCapture.StopReason
        if signpost {
            // Aggregate begin/end events into intervals, printed once capture stops.
            let result = await LogCapture.run(
                stream,
                filter: setup.filterChain,
                limits: limits,
                into: SignpostAggregator()
            ) { $0.ingest($1) }
            print(SignpostFormatter.render(
                result.state.summaries(),
                format: options.format,
                orphanEndCount: result.state.orphanEndCount
            ))
            stop = result.stop
        } else {
            let dedupWriter = options.dedup ? DedupWriter(formatter: formatter) : nil
            stop = await LogCapture.run(stream, filter: setup.filterChain, limits: limits, into: ()) { _, entry in
                if let dedupWriter {
                    dedupWriter.write(entry)
                } else {
                    print(formatter.format(entry))
                }
            }.stop
            dedupWriter?.flush()
        }

        switch stop {
        case .firstEntryTimeout:
            throw ExitCode.failure
        case .error(let error):
            throw error
        case .count, .timeout, .captureComplete, .exhausted:
            break
        }
    }
}
