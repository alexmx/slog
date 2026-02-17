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
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static func json(_ value: some Encodable) throws -> MCPToolResult {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            return .text("{\"error\": \"Failed to encode result\"}")
        }
        return .text(string)
    }

    // MARK: - Argument Types

    struct ShowArgs: MCPToolInput {
        @InputProperty("Time range: duration (e.g. '5m', '1h') or 'boot' for last boot. Start here for quick lookback.")
        var last: String?

        @InputProperty("Start date for custom range (e.g. '2024-01-15 10:30:00'). Use with 'end' instead of 'last'.")
        var start: String?

        @InputProperty("End date for custom range (e.g. '2024-01-15 11:00:00'). Optional — omit to query from start to now.")
        var end: String?

        @InputProperty("Filter by process name (use slog_list_processes to discover names)")
        var process: String?

        @InputProperty("Filter by process ID")
        var pid: Int?

        @InputProperty("Filter by subsystem (e.g. 'com.apple.network'). Automatically includes debug logs.")
        var subsystem: String?

        @InputProperty("Filter by category (use with subsystem for precise filtering)")
        var category: String?

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
        @InputProperty("Filter by process name (use slog_list_processes to discover names)")
        var process: String?

        @InputProperty("Filter by process ID")
        var pid: Int?

        @InputProperty("Filter by subsystem (e.g. 'com.apple.network'). Automatically includes debug logs.")
        var subsystem: String?

        @InputProperty("Filter by category (use with subsystem for precise filtering)")
        var category: String?

        @InputProperty("Minimum log level: debug, info, default, error, fault. Narrows results when too many entries.")
        var level: String?

        @InputProperty("Filter messages by regex pattern (client-side, applied after retrieval)")
        var grep: String?

        @InputProperty("Exclude messages matching regex (e.g. 'heartbeat|keepalive' to remove noise)")
        var exclude_grep: String?

        @InputProperty("Number of entries to capture (required, max 1000). Controls how long the stream runs.")
        var count: Int

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
        investigating what happened in the recent past. Returns log entries as JSON array. \
        Requires at least 'last', 'start', or 'archive_path'. \
        Use 'last' for recent logs (e.g. '5m', '1h', 'boot'). \
        Use 'start'/'end' for date ranges. \
        **Start with broad filters** (process only), then narrow with subsystem/level/grep. \
        When filtering by subsystem, debug logs are automatically included.
        """
    ) { (args: ShowArgs) in
        // Validate: need at least one time source
        guard args.last != nil || args.start != nil || args.archive_path != nil else {
            return .text("{\"error\": \"Specify 'last', 'start', or 'archive_path'\"}")
        }

        let setup = try FilterSetup.build(
            process: args.process,
            pid: args.pid,
            subsystem: args.subsystem,
            category: args.category,
            level: args.level.flatMap { LogLevel(string: $0) },
            grep: args.grep,
            excludeGrep: args.exclude_grep
        )

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

        do {
            for try await entry in stream {
                guard setup.filterChain.isEmpty || setup.filterChain.matches(entry) else { continue }
                entries.append(entry)
                if entries.count >= maxCount { break }
            }
        } catch is CancellationError {
            // Cancelled
        }

        return try json(entries)
    }

    static let stream = MCPTool(
        name: "slog_stream",
        description: """
        Stream live macOS/iOS logs with bounded capture. **Use this for real-time debugging** — \
        watching logs as they happen. Returns log entries as JSON array. \
        The 'count' parameter is required (max 1000) to ensure bounded capture. \
        **For investigating past events, use slog_show instead.** \
        Start with broad filters (process only), then narrow with subsystem/level/grep. \
        Supports iOS Simulator via 'simulator' flag. \
        When filtering by subsystem, debug logs are automatically included.
        """
    ) { (args: StreamArgs) in
        let count = min(args.count, 1000)
        guard count > 0 else {
            return .text("{\"error\": \"'count' must be a positive integer\"}")
        }

        let setup = try FilterSetup.build(
            process: args.process,
            pid: args.pid,
            subsystem: args.subsystem,
            category: args.category,
            level: args.level.flatMap { LogLevel(string: $0) },
            grep: args.grep,
            excludeGrep: args.exclude_grep
        )

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

        var entries: [LogEntry] = []

        do {
            for try await entry in stream {
                guard setup.filterChain.isEmpty || setup.filterChain.matches(entry) else { continue }
                entries.append(entry)
                if entries.count >= count { break }
            }
        } catch is CancellationError {
            // Cancelled
        }

        return try json(entries)
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
