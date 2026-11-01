//
//  SlogTools.swift
//  slog
//

import Foundation
import SwiftMCP

enum SlogTools {
    // MARK: - Helpers

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = LogTimestamp.jsonEncoding
        return encoder
    }()

    /// A tool failure, returned to the caller as `{ "error": …, "try_doctor"?: true }`.
    /// Set `tryDoctor` on system-level errors (missing `log` CLI, permission
    /// denied, simctl unavailable) so the agent calls `slog_doctor` once before
    /// retrying. Leave it off for validation/user errors doctor can't explain.
    struct ToolError: Error {
        let message: String
        var tryDoctor = false

        /// A system-level failure the agent should diagnose with `slog_doctor`.
        static func system(_ error: any Error) -> ToolError {
            ToolError(message: error.localizedDescription, tryDoctor: true)
        }
    }

    private struct ErrorPayload: Encodable {
        let error: String
        let tryDoctor: Bool?

        enum CodingKeys: String, CodingKey {
            case error
            case tryDoctor = "try_doctor"
        }
    }

    /// Runs a tool body and encodes its result as JSON. A thrown `ToolError`
    /// becomes the error payload as-is; any other error keeps its description
    /// and doesn't set `try_doctor`.
    static func respond(_ body: () async throws -> some Encodable) async -> MCPToolResult {
        do {
            let data = try await encoder.encode(body())
            return .text(String(decoding: data, as: UTF8.self))
        } catch let error as ToolError {
            return errorJSON(error.message, tryDoctor: error.tryDoctor)
        } catch {
            return errorJSON(error.localizedDescription, tryDoctor: false)
        }
    }

    private static func errorJSON(_ message: String, tryDoctor: Bool) -> MCPToolResult {
        let payload = ErrorPayload(error: message, tryDoctor: tryDoctor ? true : nil)
        guard let data = try? encoder.encode(payload) else {
            return .text("{\"error\":\"Failed to encode error\"}")
        }
        return .text(String(decoding: data, as: UTF8.self))
    }

    /// Parses MCP's `level` argument (any case), rejecting unknown values
    /// instead of silently dropping the level filter.
    static func parseLevel(_ value: String?) throws -> LogLevel? {
        guard let value else { return nil }
        guard let level = LogLevel(string: value) else {
            let expected = LogLevel.allValueStrings.joined(separator: ", ")
            throw ToolError(message: "Invalid 'level' '\(value)'. Expected one of: \(expected)")
        }
        return level
    }

    /// The simulator an MCP call asks for via `simulator` / `simulator_udid`.
    private static func simulatorRequest(_ simulator: Bool?, _ udid: String?) -> LogTarget.Request {
        LogTarget.Request(simulator: simulator == true, udid: udid)
    }

    /// The Mac, or the requested simulator. Lookup failures (simctl missing,
    /// no booted simulator) are system-level, so they suggest `slog_doctor`.
    private static func target(_ request: LogTarget.Request) async throws -> LogTarget {
        do {
            return try await request.resolve()
        } catch {
            throw ToolError.system(error)
        }
    }

    /// Build a `FilterSetup` from MCP's optional array arguments.
    private static func filterSetup(
        processes: [String]?,
        pid: Int?,
        subsystems: [String]?,
        categories: [String]?,
        level: String? = nil,
        grep: String? = nil,
        excludeGrep: String? = nil,
        signpost: Bool = false
    ) throws -> FilterSetup {
        try FilterSetup.build(
            processes: processes ?? [],
            pid: pid,
            subsystems: subsystems ?? [],
            categories: categories ?? [],
            level: parseLevel(level),
            grep: grep,
            excludeGrep: excludeGrep,
            signpost: signpost
        )
    }

    // MARK: - Tools

    static let show = MCPTool(
        name: "slog_show",
        description: """
        Query historical/persisted macOS logs. Requires one source: `last`, \
        `start`/`end`, `archive_path`, or `source_file` (a previous `output_file`). \
        Filtering by `subsystem` auto-includes debug+info. iOS Simulator via `simulator: true`.
        
        **Iterative drill-down:** pass a previous call's `output_file` back as `source_file` \
        to re-filter/re-summarize the NDJSON spill without re-scanning the OS log database. \
        Same filter args apply; mutex with `last`/`start`/`end`/`archive_path`.
        
        **Tailing:** every response includes `next_since` (latest matched timestamp + 1µs, \
        or null if no matches). Chain calls by passing it as the next `start` to fetch only \
        what's new; works in `summary_only` mode too.
        
        Response: `{ count, elapsed_ms, scan_capped, truncated, summary, entries?, head?, tail?, output_file?, hint? }`.
          - ≤50 entries → inline as `entries`.
          - >50 entries → `summary` (time range, by_level, top processes/subsystems/categories) + `head`/`tail` (10 each) + full payload as NDJSON at `output_file`. Drill in with `Read offset/limit` or `jq`; do not slurp.
          - `full: true` → inline every entry.
          - `summary_only: true` → just `{ count, elapsed_ms, scan_capped, summary, hint? }`. Use for aggregate questions. Mutex with `full`.
        
        `summary` always covers the full matched population, scanning up to 100,000 events. \
        `scan_capped: true` warns if that ceiling was hit — narrow the window. `limit` only caps retained entries.
        
        `hint` appears only when `count == 0`. Custom (non-Apple) subsystems don't persist debug \
        events by default; if `slog_show` returns 0 from one, use `slog_stream` for live capture \
        or pre-enable persistence via `sudo log config --subsystem <name> --mode persist:debug`.
        
        On system-level failure (log CLI missing, permission denied, etc.) the error payload \
        includes `try_doctor: true` — call `slog_doctor` once and surface its findings before retrying.
        """
    ) { (args: ShowArgs) in
        await respond {
            let full = args.full ?? false
            let summaryOnly = args.summary_only ?? false
            if full, summaryOnly {
                throw ToolError(message: "'full' and 'summary_only' are mutually exclusive")
            }

            // Validate source: exactly one of (source_file) or (last|start|archive_path)
            if let sourcePath = args.source_file {
                if args.last != nil || args.start != nil || args.end != nil || args.archive_path != nil {
                    throw ToolError(
                        message: "'source_file' is mutually exclusive with 'last'/'start'/'end'/'archive_path'"
                    )
                }
                if let outPath = args.output_file {
                    let src = NDJSONSpill.resolveUserPath(sourcePath).standardizedFileURL
                    let out = NDJSONSpill.resolveUserPath(outPath).standardizedFileURL
                    if src == out {
                        throw ToolError(
                            message: "'output_file' must differ from 'source_file' to avoid clobbering it mid-read"
                        )
                    }
                }
            } else {
                guard args.last != nil || args.start != nil || args.archive_path != nil else {
                    throw ToolError(message: "Specify 'last', 'start', 'archive_path', or 'source_file'")
                }
            }
            let simulator = simulatorRequest(args.simulator, args.simulator_udid)
            if simulator.isRequested, args.source_file != nil || args.archive_path != nil {
                throw ToolError(message: "'simulator' can't be combined with 'source_file' or 'archive_path'")
            }

            let setup = try filterSetup(
                processes: args.process,
                pid: args.pid,
                subsystems: args.subsystem,
                categories: args.category,
                level: args.level,
                grep: args.grep,
                excludeGrep: args.exclude_grep
            )

            let stream: AsyncThrowingStream<LogEntry, Error>
            if let sourcePath = args.source_file {
                // Replay a previous spill — filters/summary apply, no OS scan.
                stream = NDJSONSpill.readEntries(from: NDJSONSpill.resolveUserPath(sourcePath))
            } else {
                let config = try await ShowConfiguration(
                    target: target(simulator),
                    timeRange: ShowConfiguration.TimeRange(last: args.last, start: args.start, end: args.end),
                    archivePath: args.archive_path,
                    predicate: setup.predicate,
                    includeInfo: setup.includeInfo,
                    includeDebug: setup.includeDebug
                )
                stream = LogReader().read(configuration: config)
            }

            // `limit` caps retained entries (for inline/spill/head/tail). The summary
            // accumulator always sees the full population so aggregates aren't biased
            // toward the start of the window — capped only at the hard scan ceiling.
            let retainCap = args.limit ?? 500
            var entries: [LogEntry] = []
            var accumulator = SummaryAccumulator()
            var scanCapped = false
            let started = Date()

            do {
                for try await entry in stream {
                    guard setup.filterChain.matches(entry) else { continue }
                    accumulator.add(entry)
                    if !summaryOnly, entries.count < retainCap {
                        entries.append(entry)
                    }
                    if accumulator.count >= scanCeiling {
                        scanCapped = true
                        break
                    }
                }
            } catch is CancellationError {
                // Cancelled
            } catch let spillError as NDJSONSpill.SpillError {
                // File-level — caller's path or contents are wrong, not a system issue.
                throw spillError
            } catch {
                // Anything else from the live LogReader stream is a system-level
                // failure (log CLI missing, no stream permission, etc.).
                throw ToolError.system(error)
            }

            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            let matched = accumulator.count
            let summary = matched == 0 ? nil : accumulator.build()
            let hint = matched == 0 ? emptyShowHint(args: args) : nil
            // +1µs past the latest matched event so the next tailing call doesn't
            // re-pull the boundary entry. Null when there were no matches — caller
            // reuses their previous `since`.
            let nextSince = accumulator.lastTimestamp.map { $0.addingTimeInterval(0.000_001) }

            if summaryOnly {
                return ShowResult(
                    count: matched,
                    elapsedMs: elapsedMs,
                    scanCapped: scanCapped,
                    truncated: false,
                    summary: summary,
                    entries: nil,
                    head: nil,
                    tail: nil,
                    outputFile: nil,
                    nextSince: nextSince,
                    hint: hint
                )
            }

            let envelope = try ResultEnvelopeBuilder(
                entries: entries,
                full: full,
                outputFile: args.output_file,
                spillPrefix: "show"
            ).build()

            return ShowResult(
                count: matched,
                elapsedMs: elapsedMs,
                scanCapped: scanCapped,
                truncated: envelope.truncated,
                summary: summary,
                entries: envelope.inlineEntries,
                head: envelope.head,
                tail: envelope.tail,
                outputFile: envelope.outputFile?.path,
                nextSince: nextSince,
                hint: hint
            )
        }
    }

    /// Hard upper bound on how many matching events `slog_show` will scan in
    /// one call. Bounds wall-clock and memory on runaway windows; reflected to
    /// callers via `scan_capped: true` when hit.
    private static let scanCeiling = 100_000

    /// Reasons we can offer when `slog_show` returns 0 entries. Order matters
    /// — the most specific cause wins.
    private static func emptyShowHint(args: ShowArgs) -> String? {
        let hasSubsystem = !(args.subsystem ?? []).isEmpty
        let hasProcess = !(args.process ?? []).isEmpty
        if hasSubsystem, args.level == nil {
            return """
            No events matched. Custom subsystems often emit only debug events, \
            which aren't persisted by default — try `slog_stream` for live capture, \
            or pre-enable persistence via `sudo log config --subsystem <name> --mode persist:debug`.
            """
        }
        if hasProcess, !hasSubsystem {
            return """
            No events matched. Process-only queries see only default+ persistent events. \
            If you control the app, filter by its subsystem and use `slog_stream` for debug events.
            """
        }
        if let last = args.last, last.hasSuffix("s") || last == "1m" {
            return "No events matched. Try widening the time range (e.g. `5m` or `1h`)."
        }
        return nil
    }

    static let stream = MCPTool(
        name: "slog_stream",
        description: """
        Stream live macOS/iOS logs with bounded capture. Use for real-time debugging or \
        capturing debug events from custom subsystems (which `slog_show` can't replay).
        
        `count` is optional (1–1000). Returns when count is met or `timeout` (default 30s) \
        elapses; omit `count` to run until timeout (still capped at 1000 to bound memory). \
        Filtering by `subsystem` auto-includes debug+info. iOS Simulator via `simulator: true`.
        
        Response: `{ captured, requested, stopped_by, elapsed_ms, truncated, summary, entries?, head?, tail?, output_file? }`.
          - Envelope mirrors `slog_show`: ≤50 inline as `entries`; >50 → `summary` + `head`/`tail` + NDJSON at `output_file`. `full: true` inlines every entry.
          - `stopped_by`: `count` (success) | `timeout` | `exhausted` (rare) | `error`.
        
        When `captured == 0`, inspect `elapsed_ms` and `stopped_by` before retrying with a wider window.
        
        When `stopped_by == "error"`, the response carries `error_message` (raw failure text); \
        if also `captured == 0`, `try_doctor: true` flags a likely system/permission cause.
        
        On startup failure (simctl missing, no booted simulator, etc.) the error payload \
        includes `try_doctor: true` — call `slog_doctor` once and surface its findings before retrying.
        """
    ) { (args: StreamArgs) in
        await respond {
            // `count` is optional; omitted means "until timeout", still capped at 1000
            // so a chatty machine can't blow memory between timeout ticks.
            let count: Int
            if let explicit = args.count {
                guard explicit > 0 else {
                    throw ToolError(message: "'count' must be a positive integer")
                }
                guard explicit <= 1000 else {
                    throw ToolError(
                        message: "'count' must be <= 1000 (got \(explicit)). Use a smaller window or run multiple streams."
                    )
                }
                count = explicit
            } else {
                count = 1000
            }

            let setup = try filterSetup(
                processes: args.process,
                pid: args.pid,
                subsystems: args.subsystem,
                categories: args.category,
                level: args.level,
                grep: args.grep,
                excludeGrep: args.exclude_grep
            )

            let config = try await StreamConfiguration(
                target: target(simulatorRequest(args.simulator, args.simulator_udid)),
                predicate: setup.predicate,
                includeInfo: setup.includeInfo,
                includeDebug: setup.includeDebug
            )

            let startTime = Date()
            let (collected, stop) = await LogCapture.run(
                LogStreamer().stream(configuration: config),
                filter: setup.filterChain,
                limits: .init(count: count, timeout: .seconds(args.timeout ?? 30)),
                into: [LogEntry]()
            ) { $0.append($1) }

            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let captured = collected.count

            // Surface the failure on the response — otherwise the agent sees
            // `stopped_by: "error"` with nothing to act on.
            var streamFailure: Error?
            let stoppedBy: String
            switch stop {
            case .timeout:
                stoppedBy = "timeout"
            case .count:
                stoppedBy = "count"
            case .error(let error):
                streamFailure = error
                stoppedBy = "error"
            case .firstEntryTimeout, .captureComplete, .exhausted:
                stoppedBy = "exhausted"
            }

            let envelope = try ResultEnvelopeBuilder(
                entries: collected,
                full: args.full ?? false,
                outputFile: args.output_file,
                spillPrefix: "stream"
            ).build()

            // try_doctor heuristic: zero captured + error means the stream never
            // opened (system/permission level). Any captured entries imply the
            // stream worked initially and the error is transient/mid-flight.
            let errorMessage = streamFailure?.localizedDescription
            let tryDoctor = (streamFailure != nil && captured == 0) ? true : nil

            return StreamResult(
                captured: captured,
                requested: count,
                stoppedBy: stoppedBy,
                elapsedMs: elapsedMs,
                truncated: envelope.truncated,
                summary: collected.isEmpty ? nil : envelope.summary,
                entries: envelope.inlineEntries,
                head: envelope.head,
                tail: envelope.tail,
                outputFile: envelope.outputFile?.path,
                errorMessage: errorMessage,
                tryDoctor: tryDoctor
            )
        }
    }

    static let signpost = MCPTool(
        name: "slog_signpost",
        description: """
        Report os_signpost interval durations (begin/end pairs) for a subsystem/category — \
        the timing data behind `OSSignposter.beginInterval`/`endInterval`, without opening Instruments.
        
        Two modes:
          - **Persisted query** (default): pass `last`/`start`+`end`/`archive_path`. Reads the \
        persisted store. Custom-subsystem signposts may need `sudo log config --subsystem <name> --mode persist:debug` first.
          - **Live capture** (`live: true`): pairs intervals as events arrive over `timeout` \
        seconds (default 10). Needs no persistence — the reliable path right after driving the app.
        Either mode reads an iOS Simulator with `simulator: true`.
        
        Pairs begin↔end by (process, signpost name, signpost id), so concurrent same-name \
        intervals stay distinct. Unmatched begins are returned as in-flight (`duration_ms: null`).
        
        Response: `{ count, in_flight, orphan_ends, elapsed_ms, mode, intervals, hint? }`. \
        `intervals` is grouped by name: `{ name, subsystem, category, count, in_flight, min_ms, \
        p50_ms, max_ms, total_ms }`. Set `full: true` to add per-occurrence `occurrences` \
        (start, duration_ms, message from the begin, end_message from the end when present). \
        `hint` appears only when `count == 0`.
        """
    ) { (args: SignpostArgs) in
        await respond {
            let live = args.live ?? false

            if !live, args.last == nil, args.start == nil, args.archive_path == nil {
                throw ToolError(
                    message: "Specify 'last', 'start', or 'archive_path' (or set 'live: true' for live capture)"
                )
            }
            let simulator = simulatorRequest(args.simulator, args.simulator_udid)
            if simulator.isRequested, args.archive_path != nil {
                throw ToolError(message: "'simulator' can't be combined with 'archive_path'")
            }
            let logTarget = try await target(simulator)

            let setup = try filterSetup(
                processes: args.process,
                pid: args.pid,
                subsystems: args.subsystem,
                categories: args.category,
                signpost: true
            )

            let started = Date()
            var aggregator = SignpostAggregator()
            var stoppedBy: String?
            var errorMessage: String?
            var tryDoctor: Bool?

            if live {
                let timeoutSeconds = min(max(args.timeout ?? 10, 1), 60)
                let config = StreamConfiguration(
                    target: logTarget,
                    predicate: setup.predicate,
                    includeInfo: setup.includeInfo,
                    includeDebug: setup.includeDebug,
                    includeSignposts: true
                )
                let capture = await LogCapture.run(
                    LogStreamer().stream(configuration: config),
                    limits: .init(count: signpostLiveCap, timeout: .seconds(timeoutSeconds)),
                    into: (aggregator: SignpostAggregator(), received: 0)
                ) { state, entry in
                    state.aggregator.ingest(entry)
                    state.received += 1
                }
                aggregator = capture.state.aggregator

                switch capture.stop {
                case .timeout:
                    stoppedBy = "timeout"
                case .error(let error):
                    stoppedBy = "error"
                    errorMessage = error.localizedDescription
                    if capture.state.received == 0 {
                        tryDoctor = true
                    }
                case .count, .firstEntryTimeout, .captureComplete, .exhausted:
                    stoppedBy = "exhausted"
                }
            } else {
                let config = ShowConfiguration(
                    target: logTarget,
                    timeRange: ShowConfiguration.TimeRange(last: args.last, start: args.start, end: args.end),
                    archivePath: args.archive_path,
                    predicate: setup.predicate,
                    includeInfo: setup.includeInfo,
                    includeDebug: setup.includeDebug,
                    includeSignposts: true
                )
                do {
                    for try await entry in LogReader().read(configuration: config) {
                        aggregator.ingest(entry)
                    }
                } catch {
                    throw ToolError.system(error)
                }
            }

            let summaries = aggregator.summaries()
            let includeOccurrences = args.full ?? false
            let intervals = summaries.map { FormattedSignpost(from: $0, includeOccurrences: includeOccurrences) }
            let totalCount = summaries.reduce(0) { $0 + $1.count }
            let inFlight = summaries.reduce(0) { $0 + $1.inFlightCount }
            let hint = totalCount == 0 ? emptySignpostHint(live: live) : nil

            return SignpostResult(
                count: totalCount,
                inFlight: inFlight,
                orphanEnds: aggregator.orphanEndCount,
                elapsedMs: Int(Date().timeIntervalSince(started) * 1000),
                mode: live ? "stream" : "show",
                intervals: intervals,
                hint: hint,
                stoppedBy: stoppedBy,
                errorMessage: errorMessage,
                tryDoctor: tryDoctor
            )
        }
    }

    /// Cap on signpost events buffered during a single live capture. Bounds
    /// memory between timeout ticks for a chatty target.
    private static let signpostLiveCap = 100_000

    /// Hint when `slog_signpost` finds nothing — differs by mode.
    private static func emptySignpostHint(live: Bool) -> String {
        if live {
            return """
            No signpost intervals captured. Confirm the process emits os_signpost intervals \
            under this subsystem/category and that you exercised it during the capture window.
            """
        }
        return """
        No signpost intervals found. Custom-subsystem signposts often aren't persisted by default — \
        capture live with `live: true` while exercising the app, or pre-enable persistence via \
        `sudo log config --subsystem <name> --mode persist:debug`.
        """
    }

    static let listProcesses = MCPTool(
        name: "slog_list_processes",
        description: """
        List running macOS processes. Call first to discover names for `slog_show`/`slog_stream` \
        `process` arg. Use `filter` to narrow by name substring before truncation kicks in.
        
        Response: `{ count, truncated, processes?, head?, tail?, output_file? }`.
          - ≤50 → inline as `processes`.
          - >50 → `head`/`tail` (10 each, alphabetical) + full list as NDJSON at `output_file`.
          - `full: true` → inline every process.
        """
    ) { (args: ListProcessesArgs) in
        await respond {
            let processes: [RunningProcess]
            do {
                processes = try await SystemQuery.listProcesses(filter: args.filter)
            } catch {
                throw ToolError.system(error)
            }
            let envelope = try ListEnvelopeBuilder(
                items: processes,
                full: args.full ?? false,
                outputFile: args.output_file,
                spillPrefix: "processes"
            ).build()

            return ProcessListResult(
                count: processes.count,
                truncated: envelope.truncated,
                processes: envelope.inline,
                head: envelope.head,
                tail: envelope.tail,
                outputFile: envelope.outputFile?.path
            )
        }
    }

    static let listSimulators = MCPTool(
        name: "slog_list_simulators",
        description: "List iOS Simulators. Use to find UDIDs for `simulator_udid` on `slog_show`/`slog_stream`/`slog_signpost`. Returns array of `{name, udid, state, runtime}`."
    ) { (args: ListSimulatorsArgs) in
        await respond {
            do {
                return try await SystemQuery.listSimulators(booted: args.booted ?? false, all: args.all ?? false)
            } catch {
                throw ToolError.system(error)
            }
        }
    }

    static let doctor = MCPTool(
        name: "slog_doctor",
        description: "Check system requirements: log CLI, stream/archive access, simctl, profiles dir. Run if other tools fail unexpectedly."
    ) {
        await respond { await DoctorCheck.runAll() }
    }

    // MARK: - All Tools

    static let all: [MCPTool] = [
        show,
        stream,
        signpost,
        listProcesses,
        listSimulators,
        doctor
    ]
}
