//
//  SlogTools.swift
//  slog
//

import Foundation
import SwiftMCP

/// Thread-safe sendable one-shot flag
final class SendableBoolFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        defer { lock.unlock() }
        value = true
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Thread-safe sendable container for collecting log entries
class SendableEntryContainer: @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [LogEntry] = []

    var entries: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    func append(_ entry: LogEntry) {
        lock.lock()
        defer { lock.unlock() }
        _entries.append(entry)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _entries.count
    }
}

/// Response shape for `slog_show`. Defaults to a token-cheap envelope:
/// `summary` plus a `head`/`tail` sample with the full payload spilled to
/// `output_file` as NDJSON. Set `full: true` (or stay under the inline
/// threshold) to get all entries inline instead.
///
/// `hint` is populated only when `count == 0` and we can guess why
/// (custom-subsystem debug persistence, process-only query, too-short window).
struct ShowResult: Encodable {
    let count: Int
    let elapsedMs: Int
    let scanCapped: Bool
    let truncated: Bool
    let summary: ResultSummary?
    let entries: [LogEntry]?
    let head: [LogEntry]?
    let tail: [LogEntry]?
    let outputFile: String?
    let nextSince: Date?
    let hint: String?

    enum CodingKeys: String, CodingKey {
        case count
        case truncated
        case summary
        case entries
        case head
        case tail
        case hint
        case elapsedMs = "elapsed_ms"
        case outputFile = "output_file"
        case scanCapped = "scan_capped"
        case nextSince = "next_since"
    }
}

/// Response shape for `slog_list_processes`. Same truncation contract as
/// `ShowResult` (small results inline as `processes`; large results truncate
/// to `head`/`tail` with the full list spilled as NDJSON to `output_file`).
/// `filter` lets callers narrow before they ever hit the threshold.
struct ProcessListResult: Encodable {
    let count: Int
    let truncated: Bool
    let processes: [RunningProcess]?
    let head: [RunningProcess]?
    let tail: [RunningProcess]?
    let outputFile: String?

    enum CodingKeys: String, CodingKey {
        case count
        case truncated
        case processes
        case head
        case tail
        case outputFile = "output_file"
    }
}

/// Response shape for `slog_stream`. Same truncation contract as `ShowResult`
/// (see above) plus stream-specific diagnostics: `stoppedBy` tells callers
/// whether an empty result means "nothing matched in the time window"
/// (`timeout`) or "stream itself closed before the count was reached"
/// (`exhausted`).
struct StreamResult: Encodable {
    let captured: Int
    let requested: Int
    /// `count` (reached requested limit) | `timeout` | `exhausted` | `error`
    let stoppedBy: String
    let elapsedMs: Int
    let truncated: Bool
    let summary: ResultSummary?
    let entries: [LogEntry]?
    let head: [LogEntry]?
    let tail: [LogEntry]?
    let outputFile: String?

    enum CodingKeys: String, CodingKey {
        case captured
        case requested
        case truncated
        case summary
        case entries
        case head
        case tail
        case stoppedBy = "stopped_by"
        case elapsedMs = "elapsed_ms"
        case outputFile = "output_file"
    }
}

enum SlogTools {
    // MARK: - Helpers

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static func json(_ value: some Encodable) throws -> MCPToolResult {
        let data = try encoder.encode(value)
        return .text(String(decoding: data, as: UTF8.self))
    }

    /// `{ "error": "<message>" }` payload for tool failures. Uses the same
    /// encoder as `json` so escaping (quotes, backslashes, newlines, unicode)
    /// stays consistent with success responses.
    private static func errorJSON(_ message: String) -> MCPToolResult {
        guard let data = try? encoder.encode(["error": message]) else {
            return .text("{\"error\":\"Failed to encode error\"}")
        }
        return .text(String(decoding: data, as: UTF8.self))
    }

    /// Outcome of `buildFilterSetup`: the parsed setup or a ready-to-return
    /// error envelope. Lets MCP handlers do `switch … case .failure: return`
    /// without nested do/catch around the shared setup step.
    enum FilterSetupOutcome {
        case ok(FilterSetup)
        case failed(MCPToolResult)
    }

    /// Build a `FilterSetup` from MCP args, packaging `FilterSetupError` into
    /// an `errorJSON` payload.
    private static func buildFilterSetup(
        processes: [String]?,
        pid: Int?,
        subsystems: [String]?,
        categories: [String]?,
        level: String?,
        grep: String?,
        excludeGrep: String?
    ) -> FilterSetupOutcome {
        do {
            let setup = try FilterSetup.build(
                processes: processes ?? [],
                pid: pid,
                subsystems: subsystems ?? [],
                categories: categories ?? [],
                level: level.flatMap { LogLevel(string: $0) },
                grep: grep,
                excludeGrep: excludeGrep
            )
            return .ok(setup)
        } catch let error as FilterSetupError {
            return .failed(errorJSON(error.errorDescription ?? "\(error)"))
        } catch {
            return .failed(errorJSON("\(error)"))
        }
    }

    // MARK: - Argument Types

    struct ShowArgs: MCPToolInput {
        @InputProperty("Time range: duration ('5m', '1h') or 'boot'.")
        var last: String?

        @InputProperty("Range start, e.g. '2024-01-15 10:30:00'. Use with `end` instead of `last`.")
        var start: String?

        @InputProperty("Range end. Omit to query to now.")
        var end: String?

        @InputProperty("Process name(s), array, OR-matched. e.g. [\"Finder\", \"Dock\"].")
        var process: [String]?

        @InputProperty("Process ID.")
        var pid: Int?

        @InputProperty("Subsystem(s), array, OR-matched. Auto-includes debug+info.")
        var subsystem: [String]?

        @InputProperty("Category(ies), array, OR-matched. Pair with `subsystem`.")
        var category: [String]?

        @InputProperty("Min level: debug, info, default, error, fault.")
        var level: String?

        @InputProperty("Regex filter on message (client-side).")
        var grep: String?

        @InputProperty("Regex exclusion on message, e.g. 'heartbeat|keepalive'.")
        var exclude_grep: String?

        @InputProperty("Max entries retained for `entries`/`head`/`tail`/`output_file` (default 500). Summary always scans the full population up to 100k events.")
        var limit: Int?

        @InputProperty("Path to a .logarchive file (alternative to `last`/`start`).")
        var archive_path: String?

        @InputProperty("Re-query a previous `output_file` instead of scanning the OS log database. Cheap iterative drill-down. Mutex with `last`/`start`/`end`/`archive_path`.")
        var source_file: String?

        @InputProperty("NDJSON spill path. Defaults to `$XDG_CACHE_HOME/slog/runs/` when truncated.")
        var output_file: String?

        @InputProperty("Inline every entry, bypassing truncation. Mutex with `summary_only`.")
        var full: Bool?

        @InputProperty("Return only the aggregate summary (no entries, no spill). Mutex with `full`.")
        var summary_only: Bool?
    }

    struct StreamArgs: MCPToolInput {
        @InputProperty("Process name(s), array, OR-matched. e.g. [\"Finder\", \"Dock\"].")
        var process: [String]?

        @InputProperty("Process ID.")
        var pid: Int?

        @InputProperty("Subsystem(s), array, OR-matched. Auto-includes debug+info.")
        var subsystem: [String]?

        @InputProperty("Category(ies), array, OR-matched. Pair with `subsystem`.")
        var category: [String]?

        @InputProperty("Min level: debug, info, default, error, fault.")
        var level: String?

        @InputProperty("Regex filter on message (client-side).")
        var grep: String?

        @InputProperty("Regex exclusion on message, e.g. 'heartbeat|keepalive'.")
        var exclude_grep: String?

        @InputProperty("Stop early after this many entries (1–1000). Omit to run until `timeout`; the call still caps at 1000 to bound memory.")
        var count: Int?

        @InputProperty("Max wait seconds (default 30). Returns whatever is captured on timeout.")
        var timeout: Int?

        @InputProperty("Stream from iOS Simulator.")
        var simulator: Bool?

        @InputProperty("Simulator UDID (auto-detects if exactly one is booted).")
        var simulator_udid: String?

        @InputProperty("NDJSON spill path. Defaults to `$XDG_CACHE_HOME/slog/runs/` when truncated.")
        var output_file: String?

        @InputProperty("Inline every entry, bypassing truncation.")
        var full: Bool?
    }

    struct ListProcessesArgs: MCPToolInput {
        @InputProperty("Name substring filter (case-insensitive).")
        var filter: String?

        @InputProperty("NDJSON spill path. Defaults to `$XDG_CACHE_HOME/slog/runs/` when truncated.")
        var output_file: String?

        @InputProperty("Inline every process, bypassing truncation.")
        var full: Bool?
    }

    struct ListSimulatorsArgs: MCPToolInput {
        @InputProperty("Only booted simulators (the streamable ones).")
        var booted: Bool?

        @InputProperty("Include unavailable simulators (uninstalled runtimes).")
        var all: Bool?
    }

    // MARK: - Tools

    static let show = MCPTool(
        name: "slog_show",
        description: """
        Query historical/persisted macOS logs. Requires one source: `last`, \
        `start`/`end`, `archive_path`, or `source_file` (a previous `output_file`). \
        Filtering by `subsystem` auto-includes debug+info.

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
        """
    ) { (args: ShowArgs) in
        let full = args.full ?? false
        let summaryOnly = args.summary_only ?? false
        if full, summaryOnly {
            return errorJSON("'full' and 'summary_only' are mutually exclusive")
        }

        // Validate source: exactly one of (source_file) or (last|start|archive_path)
        if let sourcePath = args.source_file {
            if args.last != nil || args.start != nil || args.end != nil || args.archive_path != nil {
                return errorJSON(
                    "'source_file' is mutually exclusive with 'last'/'start'/'end'/'archive_path'"
                )
            }
            if let outPath = args.output_file {
                let src = NDJSONSpill.resolveUserPath(sourcePath).standardizedFileURL
                let out = NDJSONSpill.resolveUserPath(outPath).standardizedFileURL
                if src == out {
                    return errorJSON("'output_file' must differ from 'source_file' to avoid clobbering it mid-read")
                }
            }
        } else {
            guard args.last != nil || args.start != nil || args.archive_path != nil else {
                return errorJSON("Specify 'last', 'start', 'archive_path', or 'source_file'")
            }
        }

        let setup: FilterSetup
        switch buildFilterSetup(
            processes: args.process,
            pid: args.pid,
            subsystems: args.subsystem,
            categories: args.category,
            level: args.level,
            grep: args.grep,
            excludeGrep: args.exclude_grep
        ) {
        case .ok(let value): setup = value
        case .failed(let result): return result
        }

        let stream: AsyncThrowingStream<LogEntry, Error>
        if let sourcePath = args.source_file {
            // Replay a previous spill — filters/summary apply, no OS scan.
            stream = NDJSONSpill.readEntries(from: NDJSONSpill.resolveUserPath(sourcePath))
        } else {
            let timeRange: ShowConfiguration.TimeRange? = if let last = args.last {
                if last.lowercased() == "boot" {
                    .lastBoot
                } else {
                    .last(last)
                }
            } else if let start = args.start {
                if let end = args.end {
                    .range(start: start, end: end)
                } else {
                    .start(start)
                }
            } else {
                nil
            }

            let config = ShowConfiguration(
                timeRange: timeRange,
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
                guard setup.filterChain.isEmpty || setup.filterChain.matches(entry) else { continue }
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
        } catch {
            // Surface NDJSONSpill read/parse errors (and any other stream errors)
            // rather than silently returning a zero-count result.
            return errorJSON(error.localizedDescription)
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
            return try json(ShowResult(
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
            ))
        }

        let envelope: ResultEnvelopeBuilder.Output
        do {
            envelope = try ResultEnvelopeBuilder(
                entries: entries,
                full: full,
                outputFile: args.output_file,
                spillPrefix: "show"
            ).build()
        } catch {
            return errorJSON(error.localizedDescription)
        }

        return try json(ShowResult(
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
        ))
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
        """
    ) { (args: StreamArgs) in
        // `count` is optional; omitted means "until timeout", still capped at 1000
        // so a chatty machine can't blow memory between timeout ticks.
        let count: Int
        if let explicit = args.count {
            guard explicit > 0 else {
                return errorJSON("'count' must be a positive integer")
            }
            guard explicit <= 1000 else {
                return errorJSON(
                    "'count' must be <= 1000 (got \(explicit)). Use a smaller window or run multiple streams."
                )
            }
            count = explicit
        } else {
            count = 1000
        }

        let setup: FilterSetup
        switch buildFilterSetup(
            processes: args.process,
            pid: args.pid,
            subsystems: args.subsystem,
            categories: args.category,
            level: args.level,
            grep: args.grep,
            excludeGrep: args.exclude_grep
        ) {
        case .ok(let value): setup = value
        case .failed(let result): return result
        }

        let target: StreamConfiguration.Target
        if args.simulator == true {
            let udid = try SystemQuery.resolveSimulatorUDID(args.simulator_udid)
            target = .simulator(udid: udid)
        } else {
            target = .local
        }

        let config = StreamConfiguration(
            target: target,
            predicate: setup.predicate,
            includeInfo: setup.includeInfo,
            includeDebug: setup.includeDebug
        )

        let streamer = LogStreamer()
        let stream = streamer.stream(configuration: config)
        let timeoutSeconds = args.timeout ?? 30
        let filterChain = setup.filterChain

        let container = SendableEntryContainer()
        let startTime = Date()
        let timedOut = SendableBoolFlag()

        // Stream collection task
        let streamTask = Task {
            for try await entry in stream {
                guard filterChain.isEmpty || filterChain.matches(entry) else { continue }
                container.append(entry)
                if container.count >= count { break }
            }
        }

        // Timeout task — cancels stream if it takes too long
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeoutSeconds))
            timedOut.set()
            streamTask.cancel()
        }

        // Wait for stream to finish (either by count or cancellation)
        let streamResult = await streamTask.result
        timeoutTask.cancel()

        let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let captured = container.count
        let stoppedBy = if timedOut.get() {
            "timeout"
        } else if case .failure = streamResult {
            "error"
        } else if captured >= count {
            "count"
        } else {
            "exhausted"
        }

        let collected = container.entries
        let envelope: ResultEnvelopeBuilder.Output
        do {
            envelope = try ResultEnvelopeBuilder(
                entries: collected,
                full: args.full ?? false,
                outputFile: args.output_file,
                spillPrefix: "stream"
            ).build()
        } catch {
            return errorJSON(error.localizedDescription)
        }

        let result = StreamResult(
            captured: captured,
            requested: count,
            stoppedBy: stoppedBy,
            elapsedMs: elapsedMs,
            truncated: envelope.truncated,
            summary: collected.isEmpty ? nil : envelope.summary,
            entries: envelope.inlineEntries,
            head: envelope.head,
            tail: envelope.tail,
            outputFile: envelope.outputFile?.path
        )
        return try json(result)
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
        let processes = try SystemQuery.listProcesses(filter: args.filter)
        let envelope: ListEnvelopeBuilder<RunningProcess>.Output
        do {
            envelope = try ListEnvelopeBuilder(
                items: processes,
                full: args.full ?? false,
                outputFile: args.output_file,
                spillPrefix: "processes"
            ).build()
        } catch {
            return errorJSON(error.localizedDescription)
        }

        return try json(ProcessListResult(
            count: processes.count,
            truncated: envelope.truncated,
            processes: envelope.inline,
            head: envelope.head,
            tail: envelope.tail,
            outputFile: envelope.outputFile?.path
        ))
    }

    static let listSimulators = MCPTool(
        name: "slog_list_simulators",
        description: "List iOS Simulators. Use to find UDIDs for `slog_stream` with `simulator: true`. Returns array of `{name, udid, state, runtime}`."
    ) { (args: ListSimulatorsArgs) in
        let simulators = try SystemQuery.listSimulators(
            booted: args.booted ?? false,
            all: args.all ?? false
        )
        return try json(simulators)
    }

    static let doctor = MCPTool(
        name: "slog_doctor",
        description: "Check system requirements: log CLI, stream/archive access, simctl, profiles dir. Run if other tools fail unexpectedly."
    ) {
        let checks = DoctorCheck.runAll()
        return try json(checks)
    }

    // MARK: - All Tools

    static let all: [MCPTool] = [
        show,
        stream,
        listProcesses,
        listSimulators,
        doctor
    ]
}
