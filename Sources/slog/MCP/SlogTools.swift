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

/// Response shape for `slog_show`. Mirrors `StreamResult` so callers can
/// tell an empty result from a misconfigured filter — `hint` is populated
/// only when `count == 0` and we can guess why (custom-subsystem debug
/// persistence, process-only query, too-short window).
struct ShowResult: Encodable {
    let entries: [LogEntry]
    let count: Int
    let elapsedMs: Int
    let hint: String?

    enum CodingKeys: String, CodingKey {
        case entries
        case count
        case hint
        case elapsedMs = "elapsed_ms"
    }
}

/// Response shape for `slog_stream`. Wraps entries with diagnostic metadata
/// so callers can tell whether an empty result means "nothing matched in the
/// time window" (`stoppedBy: timeout`) vs "filter caught nothing and the stream
/// itself closed" (`exhausted`).
struct StreamResult: Encodable {
    let entries: [LogEntry]
    let captured: Int
    let requested: Int
    /// `count` (reached requested limit) | `timeout` | `exhausted` | `error`
    let stoppedBy: String
    let elapsedMs: Int

    enum CodingKeys: String, CodingKey {
        case entries
        case captured
        case requested
        case stoppedBy = "stopped_by"
        case elapsedMs = "elapsed_ms"
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
    }

    struct ListProcessesArgs: MCPToolInput {
        @InputProperty("Filter processes by name (case-insensitive). Omit to list all running processes.")
        var filter: String?
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
        
        Returns `{ entries, count, elapsed_ms, hint? }`. The optional `hint` appears \
        only when `count == 0` and explains the most likely cause (e.g. custom-subsystem \
        debug persistence, process-only query, time window too short).
        
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
        let result = ShowResult(
            entries: entries,
            count: entries.count,
            elapsedMs: elapsedMs,
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
        
        Returns `{ entries, captured, requested, stopped_by, elapsed_ms }`. `stopped_by`:
          - "count"     — reached `requested` entries (success path)
          - "timeout"   — hit `timeout` seconds without enough matches
          - "exhausted" — stream closed before count/timeout (rare)
          - "error"     — underlying `log stream` failed
        When `entries` is empty, inspect `elapsed_ms` and `stopped_by` to decide whether to \
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

        let result = StreamResult(
            entries: container.entries,
            captured: captured,
            requested: count,
            stoppedBy: stoppedBy,
            elapsedMs: elapsedMs
        )
        return try json(result)
    }

    static let listProcesses = MCPTool(
        name: "slog_list_processes",
        description: "List running macOS processes. **Use this first** to discover process names for filtering with slog_show or slog_stream. Returns JSON array of {name, pid} objects."
    ) { (args: ListProcessesArgs) in
        let processes = try SystemQuery.listProcesses(filter: args.filter)
        return try json(processes)
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
