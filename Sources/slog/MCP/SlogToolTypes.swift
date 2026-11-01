//
//  SlogToolTypes.swift
//  slog
//

import Foundation
import SwiftMCP

// MARK: - Responses

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
    /// Underlying failure description when `stoppedBy == "error"`. Lets agents
    /// distinguish "stream crashed" from "no matches" without parsing log noise.
    let errorMessage: String?
    /// Set when `stoppedBy == "error"` AND `captured == 0` — heuristic for
    /// "stream never opened, probably system/permission level." Mid-flight
    /// failures (some entries captured) skip the flag since doctor won't help.
    let tryDoctor: Bool?

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
        case errorMessage = "error_message"
        case tryDoctor = "try_doctor"
    }
}

/// Response shape for `slog_signpost`. Aggregated os_signpost intervals grouped
/// by name, with per-name duration stats. `mode` distinguishes the persisted
/// `show` query from a live `stream` capture. `hint` is populated only when
/// `count == 0`.
struct SignpostResult: Encodable {
    /// Total interval occurrences across all names (completed + in-flight).
    let count: Int
    let inFlight: Int
    let orphanEnds: Int
    let elapsedMs: Int
    /// `show` (persisted query) | `stream` (live capture).
    let mode: String
    let intervals: [FormattedSignpost]
    let hint: String?
    /// Live-capture only: `timeout` | `exhausted` | `error`.
    let stoppedBy: String?
    let errorMessage: String?
    let tryDoctor: Bool?

    enum CodingKeys: String, CodingKey {
        case count
        case mode
        case intervals
        case hint
        case inFlight = "in_flight"
        case orphanEnds = "orphan_ends"
        case elapsedMs = "elapsed_ms"
        case stoppedBy = "stopped_by"
        case errorMessage = "error_message"
        case tryDoctor = "try_doctor"
    }
}

// MARK: - Arguments

extension SlogTools {
    struct ShowArgs: MCPToolInput {
        @InputProperty("Time range: duration ('5m', '1h') or 'boot'.")
        var last: String?

        @InputProperty("Range start, e.g. '2024-01-15 10:30:00'. Use with `end` instead of `last`.")
        var start: String?

        @InputProperty("Range end. Omit to query to now.")
        var end: String?

        @InputProperty(
            "Process name(s), array, OR-matched, exact case-sensitive match. e.g. [\"Finder\", \"Dock\"]. Skip `slog_list_processes` if you have a confident name."
        )
        var process: [String]?

        @InputProperty("Process ID.")
        var pid: Int?

        @InputProperty("Subsystem(s), array, OR-matched. Auto-includes debug+info.")
        var subsystem: [String]?

        @InputProperty("Category(ies), array, OR-matched. Pair with `subsystem`.")
        var category: [String]?

        @InputProperty(
            "Min level (this level and above): debug, info, default, error, fault. `error` matches error+fault, not error alone."
        )
        var level: String?

        @InputProperty("Regex filter on message (client-side).")
        var grep: String?

        @InputProperty("Regex exclusion on message, e.g. 'heartbeat|keepalive'.")
        var exclude_grep: String?

        @InputProperty(
            "Max entries retained for `entries`/`head`/`tail`/`output_file` (default 500). Summary always scans the full population up to 100k events."
        )
        var limit: Int?

        @InputProperty("Path to a .logarchive file (alternative to `last`/`start`).")
        var archive_path: String?

        @InputProperty(
            "Re-query a previous `output_file` instead of scanning the OS log database. Cheap iterative drill-down. Mutex with `last`/`start`/`end`/`archive_path`."
        )
        var source_file: String?

        @InputProperty("NDJSON spill path. Defaults to `$XDG_CACHE_HOME/slog/runs/` when truncated.")
        var output_file: String?

        @InputProperty("Inline every entry, bypassing truncation. Mutex with `summary_only`.")
        var full: Bool?

        @InputProperty("Return only the aggregate summary (no entries, no spill). Mutex with `full`.")
        var summary_only: Bool?
    }

    struct StreamArgs: MCPToolInput {
        @InputProperty(
            "Process name(s), array, OR-matched, exact case-sensitive match. e.g. [\"Finder\", \"Dock\"]. Skip `slog_list_processes` if you have a confident name."
        )
        var process: [String]?

        @InputProperty("Process ID.")
        var pid: Int?

        @InputProperty("Subsystem(s), array, OR-matched. Auto-includes debug+info.")
        var subsystem: [String]?

        @InputProperty("Category(ies), array, OR-matched. Pair with `subsystem`.")
        var category: [String]?

        @InputProperty(
            "Min level (this level and above): debug, info, default, error, fault. `error` matches error+fault, not error alone."
        )
        var level: String?

        @InputProperty("Regex filter on message (client-side).")
        var grep: String?

        @InputProperty("Regex exclusion on message, e.g. 'heartbeat|keepalive'.")
        var exclude_grep: String?

        @InputProperty(
            "Stop early after this many entries (1–1000). Omit to run until `timeout`; the call still caps at 1000 to bound memory."
        )
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

    struct SignpostArgs: MCPToolInput {
        @InputProperty(
            "Time range for the persisted query: duration ('5m', '1h') or 'boot'. Ignored when `live: true`."
        )
        var last: String?

        @InputProperty("Range start, e.g. '2024-01-15 10:30:00'. Use with `end` instead of `last`.")
        var start: String?

        @InputProperty("Range end. Omit to query to now.")
        var end: String?

        @InputProperty("Path to a .logarchive file (alternative to `last`/`start`).")
        var archive_path: String?

        @InputProperty(
            "Subsystem(s), array, OR-matched. Strongly recommended — signposts are keyed by subsystem (e.g. [\"com.myapp\"])."
        )
        var subsystem: [String]?

        @InputProperty("Category(ies), array, OR-matched. Pair with `subsystem` (e.g. [\"perf\"]).")
        var category: [String]?

        @InputProperty("Process name(s), array, OR-matched, exact case-sensitive match.")
        var process: [String]?

        @InputProperty("Process ID.")
        var pid: Int?

        @InputProperty(
            "Capture live instead of querying history. Pairs begin/end as events arrive and needs no persistence — the reliable path right after exercising the app."
        )
        var live: Bool?

        @InputProperty("Live capture seconds (default 10, max 60). Only with `live: true`.")
        var timeout: Int?

        @InputProperty(
            "Include per-occurrence detail (start, duration_ms, message, end_message) for each interval. Default false: aggregate stats only (token-cheap)."
        )
        var full: Bool?
    }
}
