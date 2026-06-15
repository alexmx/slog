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
    let truncated: Bool
    let summary: ResultSummary?
    let entries: [LogEntry]?
    let head: [LogEntry]?
    let tail: [LogEntry]?
    let outputFile: String?
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
        @InputProperty("Time range: duration (e.g. '5m', '1h') or 'boot' for last boot. Start here for quick lookback.")
        var last: String?

        @InputProperty("Start date for custom range (e.g. '2024-01-15 10:30:00'). Use with 'end' instead of 'last'.")
        var start: String?

        @InputProperty(
            "End date for custom range (e.g. '2024-01-15 11:00:00'). Optional — omit to query from start to now."
        )
        var end: String?

        @InputProperty(
            "Filter by process name(s) — array, OR-matched (use slog_list_processes to discover names). Example: [\"Finder\", \"Dock\"]."
        )
        var process: [String]?

        @InputProperty("Filter by process ID")
        var pid: Int?

        @InputProperty(
            "Filter by subsystem(s) — array, OR-matched (e.g. [\"com.apple.network\"]). Automatically includes debug logs."
        )
        var subsystem: [String]?

        @InputProperty(
            "Filter by category(ies) — array, OR-matched (use with subsystem for precise filtering). Example: [\"http\", \"dns\"]."
        )
        var category: [String]?

        @InputProperty("Minimum log level: debug, info, default, error, fault. Narrows results when too many entries.")
        var level: String?

        @InputProperty("Filter messages by regex pattern (client-side, applied after retrieval)")
        var grep: String?

        @InputProperty("Exclude messages matching regex (e.g. 'heartbeat|keepalive' to remove noise)")
        var exclude_grep: String?

        @InputProperty("Maximum number of entries to return (default: 500)")
        var count: Int?

        @InputProperty("Path to a .logarchive file (alternative to last/start)")
        var archive_path: String?

        @InputProperty(
            "Path to write the full result set as NDJSON (one entry per line). When omitted and the result exceeds the inline threshold, writes to `$XDG_CACHE_HOME/slog/runs/`. Use `Read offset/limit` or `jq` on this file to drill in."
        )
        var output_file: String?

        @InputProperty(
            "Return every entry inline instead of the default summary+head+tail envelope. Off by default — only set this when you genuinely need the full payload in the response."
        )
        var full: Bool?
    }

    struct StreamArgs: MCPToolInput {
        @InputProperty(
            "Filter by process name(s) — array, OR-matched (use slog_list_processes to discover names). Example: [\"Finder\", \"Dock\"]."
        )
        var process: [String]?

        @InputProperty("Filter by process ID")
        var pid: Int?

        @InputProperty(
            "Filter by subsystem(s) — array, OR-matched (e.g. [\"com.apple.network\"]). Automatically includes debug logs."
        )
        var subsystem: [String]?

        @InputProperty(
            "Filter by category(ies) — array, OR-matched (use with subsystem for precise filtering). Example: [\"http\", \"dns\"]."
        )
        var category: [String]?

        @InputProperty("Minimum log level: debug, info, default, error, fault. Narrows results when too many entries.")
        var level: String?

        @InputProperty("Filter messages by regex pattern (client-side, applied after retrieval)")
        var grep: String?

        @InputProperty("Exclude messages matching regex (e.g. 'heartbeat|keepalive' to remove noise)")
        var exclude_grep: String?

        @InputProperty("Number of entries to capture (required, max 1000). Controls how long the stream runs.")
        var count: Int

        @InputProperty(
            "Maximum time to wait in seconds (default: 30). Stream returns collected entries when timeout is reached, even if count hasn't been met."
        )
        var timeout: Int?

        @InputProperty("Stream from iOS Simulator instead of host (use slog_list_simulators to find devices)")
        var simulator: Bool?

        @InputProperty("Simulator UDID (auto-detects if only one booted). Use slog_list_simulators to find UDIDs.")
        var simulator_udid: String?

        @InputProperty(
            "Path to write the full result set as NDJSON (one entry per line). When omitted and the result exceeds the inline threshold, writes to `$XDG_CACHE_HOME/slog/runs/`. Use `Read offset/limit` or `jq` on this file to drill in."
        )
        var output_file: String?

        @InputProperty(
            "Return every entry inline instead of the default summary+head+tail envelope. Off by default — only set this when you genuinely need the full payload in the response."
        )
        var full: Bool?
    }

    struct ListProcessesArgs: MCPToolInput {
        @InputProperty("Filter processes by name (case-insensitive). Omit to list all running processes.")
        var filter: String?

        @InputProperty(
            "Path to write the full process list as NDJSON (one entry per line). When omitted and the result exceeds the inline threshold, writes to `$XDG_CACHE_HOME/slog/runs/`."
        )
        var output_file: String?

        @InputProperty(
            "Return every process inline instead of the default truncated head+tail envelope. Off by default — set this only when you need the full list in the response."
        )
        var full: Bool?
    }

    struct ListSimulatorsArgs: MCPToolInput {
        @InputProperty("Show only booted simulators (recommended — these are the ones you can stream from)")
        var booted: Bool?

        @InputProperty("Include unavailable simulators (runtimes not installed)")
        var all: Bool?
    }

    // MARK: - Tools

    static let show = MCPTool(
        name: "slog_show",
        description: """
        Query historical/persisted macOS logs. **Use this for post-mortem analysis** — \
        investigating what happened in the recent past.

        Requires one time source: `last` ('5m', '1h', 'boot'), `start`/`end` date range, \
        or `archive_path`. Start with broad filters (process only), then narrow with \
        subsystem/level/grep. Filtering by `subsystem` auto-includes debug+info; \
        otherwise only default+ levels are returned.

        **Response shape (default):** `{ count, elapsed_ms, truncated, summary, entries?, head?, tail?, output_file?, hint? }`. \
        Small result sets (≤50 entries) come back fully inline as `entries`. Larger sets \
        are truncated by default: `summary` (time range, by-level counts, top processes/\
        subsystems/categories), plus `head` and `tail` samples (10 each), and the complete \
        payload written as NDJSON to `output_file`. Read that file selectively with `Read \
        offset/limit` or `jq` — do NOT slurp the whole file unless you actually need it. \
        Set `full: true` to bypass truncation and inline every entry. Supply `output_file` \
        to control where the NDJSON lands; otherwise it goes under `$XDG_CACHE_HOME/slog/runs/`.

        The optional `hint` appears only when `count == 0` and explains the most likely cause.

        **Note on debug events:** Custom (non-Apple) subsystems do not persist debug-level \
        events by default — `log show` cannot replay them after the fact, even with --debug. \
        If you see 0 results from a subsystem you know is logging, use `slog_stream` for \
        live capture instead, or enable persistence once via \
        `sudo log config --subsystem <name> --mode persist:debug`.
        """
    ) { (args: ShowArgs) in
        // Validate: need at least one time source
        guard args.last != nil || args.start != nil || args.archive_path != nil else {
            return errorJSON("Specify 'last', 'start', or 'archive_path'")
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

        // Determine time range
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

        let reader = LogReader()
        let stream = reader.read(configuration: config)

        var entries: [LogEntry] = []
        let maxCount = args.count ?? 500
        let started = Date()

        do {
            for try await entry in stream {
                guard setup.filterChain.isEmpty || setup.filterChain.matches(entry) else { continue }
                entries.append(entry)
                if entries.count >= maxCount { break }
            }
        } catch is CancellationError {
            // Cancelled
        }

        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        let envelope: ResultEnvelopeBuilder.Output
        do {
            envelope = try ResultEnvelopeBuilder(
                entries: entries,
                full: args.full ?? false,
                outputFile: args.output_file,
                spillPrefix: "show"
            ).build()
        } catch {
            return errorJSON(error.localizedDescription)
        }

        let result = ShowResult(
            count: entries.count,
            elapsedMs: elapsedMs,
            truncated: envelope.truncated,
            summary: entries.isEmpty ? nil : envelope.summary,
            entries: envelope.inlineEntries,
            head: envelope.head,
            tail: envelope.tail,
            outputFile: envelope.outputFile?.path,
            hint: entries.isEmpty ? emptyShowHint(args: args) : nil
        )
        return try json(result)
    }

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
        Stream live macOS/iOS logs with bounded capture. **Use this for real-time debugging** \
        and for capturing debug events from your own app's subsystem (which `slog_show` cannot \
        see unless persistence was pre-enabled).

        `count` is required and must be 1–1000; the call returns as soon as that many entries \
        match, or `timeout` seconds pass (default 30s), whichever comes first. Start with broad \
        filters (process only), then narrow with subsystem/level/grep. Filtering by `subsystem` \
        auto-includes debug+info. iOS Simulator capture via `simulator: true`.

        **Response shape (default):** `{ captured, requested, stopped_by, elapsed_ms, truncated, summary, entries?, head?, tail?, output_file? }`. \
        Small captures (≤50 entries) come back fully inline as `entries`. Larger captures are \
        truncated by default: `summary` plus `head`/`tail` samples, with the complete payload \
        written as NDJSON to `output_file`. Read that file selectively with `Read offset/limit` \
        or `jq`. Set `full: true` to inline every entry. Supply `output_file` to control where \
        the NDJSON lands; otherwise it goes under `$XDG_CACHE_HOME/slog/runs/`.

        `stopped_by`:
          - "count"     — reached `requested` entries (success path)
          - "timeout"   — hit `timeout` seconds without enough matches
          - "exhausted" — stream closed before count/timeout (rare)
          - "error"     — underlying `log stream` failed
        When `captured == 0`, inspect `elapsed_ms` and `stopped_by` to decide whether to \
        retry with a wider window or a different filter.
        """
    ) { (args: StreamArgs) in
        guard args.count > 0 else {
            return errorJSON("'count' must be a positive integer")
        }
        guard args.count <= 1000 else {
            return errorJSON(
                "'count' must be <= 1000 (got \(args.count)). Use a smaller window or run multiple streams."
            )
        }
        let count = args.count

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
        List running macOS processes. **Use this first** to discover process names for \
        filtering with slog_show or slog_stream. Use `filter` to narrow by name substring \
        before truncation kicks in.

        **Response shape:** `{ count, truncated, processes?, head?, tail?, output_file? }`. \
        Small result sets (≤50 processes) come back fully inline as `processes`. Larger sets \
        are truncated by default: `head` and `tail` samples (10 each, alphabetical), with the \
        complete list written as NDJSON to `output_file` — read selectively with `Read \
        offset/limit` or `jq`. Set `full: true` to inline every process. Supply `output_file` \
        to control where the NDJSON lands; otherwise it goes under `$XDG_CACHE_HOME/slog/runs/`.
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
        description: "List iOS Simulators. Use this to find simulator UDIDs for streaming logs with slog_stream's 'simulator' flag. Returns JSON array of {name, udid, state, runtime} objects."
    ) { (args: ListSimulatorsArgs) in
        let simulators = try SystemQuery.listSimulators(
            booted: args.booted ?? false,
            all: args.all ?? false
        )
        return try json(simulators)
    }

    static let doctor = MCPTool(
        name: "slog_doctor",
        description: "Check system requirements for slog. Run this if other tools fail unexpectedly — it verifies log CLI access, stream/archive access, simulator support, and profile directory. Returns JSON object with check results."
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
