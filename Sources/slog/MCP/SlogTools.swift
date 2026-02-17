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
        @InputProperty("Time range: duration (e.g. 5m, 1h) or 'boot' for last boot")
        var last: String?

        @InputProperty("Start date (e.g. '2024-01-15 10:30:00')")
        var start: String?

        @InputProperty("End date (e.g. '2024-01-15 11:00:00')")
        var end: String?

        @InputProperty("Filter by process name")
        var process: String?

        @InputProperty("Filter by process ID")
        var pid: Int?

        @InputProperty("Filter by subsystem (e.g. com.apple.network)")
        var subsystem: String?

        @InputProperty("Filter by category")
        var category: String?

        @InputProperty("Minimum log level: debug, info, default, error, fault")
        var level: String?

        @InputProperty("Filter messages by regex pattern")
        var grep: String?

        @InputProperty("Exclude messages matching regex pattern")
        var exclude_grep: String?

        @InputProperty("Maximum number of entries to return")
        var count: Int?

        @InputProperty("Path to a .logarchive file")
        var archive_path: String?
    }

    struct StreamArgs: MCPToolInput {
        @InputProperty("Filter by process name")
        var process: String?

        @InputProperty("Filter by process ID")
        var pid: Int?

        @InputProperty("Filter by subsystem (e.g. com.apple.network)")
        var subsystem: String?

        @InputProperty("Filter by category")
        var category: String?

        @InputProperty("Minimum log level: debug, info, default, error, fault")
        var level: String?

        @InputProperty("Filter messages by regex pattern")
        var grep: String?

        @InputProperty("Exclude messages matching regex pattern")
        var exclude_grep: String?

        @InputProperty("Number of entries to capture (required, max 1000)")
        var count: Int

        @InputProperty("Stream from iOS Simulator instead of host")
        var simulator: Bool?

        @InputProperty("Simulator UDID (auto-detects if only one booted)")
        var simulator_udid: String?
    }

    struct ListProcessesArgs: MCPToolInput {
        @InputProperty("Filter processes by name (case-insensitive)")
        var filter: String?
    }

    struct ListSimulatorsArgs: MCPToolInput {
        @InputProperty("Show only booted simulators")
        var booted: Bool?

        @InputProperty("Include unavailable simulators")
        var all: Bool?
    }

    // MARK: - Tools

    static let show = MCPTool(
        name: "slog_show",
        description: """
            Query historical/persisted macOS logs. Returns log entries as JSON array. \
            Requires at least 'last', 'start', or 'archive_path'. \
            Use 'last' for recent logs (e.g. '5m', '1h', 'boot'). \
            Use 'start'/'end' for date ranges.
            """
    ) { (args: ShowArgs) in
        // Validate: need at least one time source
        guard args.last != nil || args.start != nil || args.archive_path != nil else {
            return .text("{\"error\": \"Specify 'last', 'start', or 'archive_path'\"}")
        }

        let resolvedLevel = args.level.flatMap { LogLevel(string: $0) }

        // Build server-side predicate
        let predicate = PredicateBuilder.buildPredicate(
            process: args.process,
            pid: args.pid,
            subsystem: args.subsystem,
            category: args.category,
            level: resolvedLevel
        )

        // Build client-side filter chain
        var filterChain = FilterChain()
        if let grep = args.grep {
            filterChain.messageRegex(grep)
        }
        if let excludeGrep = args.exclude_grep {
            filterChain.excludeMessageRegex(excludeGrep)
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

        // Log level inclusion
        let autoDebug = args.subsystem != nil && resolvedLevel == nil
        let includeDebug = autoDebug
        let includeInfo = includeDebug

        let config = ShowConfiguration(
            timeRange: timeRange,
            archivePath: args.archive_path,
            predicate: predicate,
            includeInfo: includeInfo,
            includeDebug: includeDebug
        )

        let reader = LogReader()
        let stream = reader.read(configuration: config)

        var entries: [LogEntry] = []
        let maxCount = args.count ?? 500

        do {
            for try await entry in stream {
                guard filterChain.isEmpty || filterChain.matches(entry) else { continue }
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
            Stream live macOS/iOS logs with bounded capture. Returns log entries as JSON array. \
            The 'count' parameter is required (max 1000) to ensure bounded capture. \
            Use filters to narrow results. Supports iOS Simulator via 'simulator' flag.
            """
    ) { (args: StreamArgs) in
        let count = min(args.count, 1000)
        guard count > 0 else {
            return .text("{\"error\": \"'count' must be a positive integer\"}")
        }

        let resolvedLevel = args.level.flatMap { LogLevel(string: $0) }

        let predicate = PredicateBuilder.buildPredicate(
            process: args.process,
            pid: args.pid,
            subsystem: args.subsystem,
            category: args.category,
            level: resolvedLevel
        )

        var filterChain = FilterChain()
        if let grep = args.grep {
            filterChain.messageRegex(grep)
        }
        if let excludeGrep = args.exclude_grep {
            filterChain.excludeMessageRegex(excludeGrep)
        }

        let target: StreamConfiguration.Target
        if args.simulator == true {
            if let udid = args.simulator_udid {
                target = .simulator(udid: udid)
            } else {
                // Auto-detect booted simulator
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["simctl", "list", "devices", "booted", "-j"]
                let pipe = Pipe()
                process.standardOutput = pipe
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let devices = json["devices"] as? [String: [[String: Any]]]
                else {
                    return .text("{\"error\": \"Could not parse simulator list\"}")
                }

                var foundUDID: String?
                for (_, deviceList) in devices {
                    for device in deviceList {
                        if let state = device["state"] as? String, state == "Booted",
                           let udid = device["udid"] as? String
                        {
                            foundUDID = udid
                            break
                        }
                    }
                    if foundUDID != nil { break }
                }

                guard let udid = foundUDID else {
                    return .text("{\"error\": \"No booted simulator found\"}")
                }
                target = .simulator(udid: udid)
            }
        } else {
            target = .local
        }

        let autoDebug = args.subsystem != nil && resolvedLevel == nil
        let includeDebug = autoDebug
        let includeInfo = includeDebug

        let config = StreamConfiguration(
            target: target,
            predicate: predicate,
            includeInfo: includeInfo,
            includeDebug: includeDebug
        )

        let streamer = LogStreamer()
        let stream = streamer.stream(configuration: config)

        var entries: [LogEntry] = []

        do {
            for try await entry in stream {
                guard filterChain.isEmpty || filterChain.matches(entry) else { continue }
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
        description: "List running macOS processes. Returns JSON array of {name, pid} objects."
    ) { (args: ListProcessesArgs) in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,comm"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return .text("{\"error\": \"Failed to read process list\"}")
        }

        let lines = output.split(separator: "\n").dropFirst()

        struct ProcessInfo: Encodable {
            let name: String
            let pid: Int
        }

        var processes: [ProcessInfo] = []
        var seen = Set<String>()

        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }

            let name = URL(fileURLWithPath: String(parts[1])).lastPathComponent

            if let filter = args.filter?.lowercased() {
                guard name.lowercased().contains(filter) else { continue }
            }

            if seen.insert(name).inserted {
                processes.append(ProcessInfo(name: name, pid: pid))
            }
        }

        processes.sort { $0.name.lowercased() < $1.name.lowercased() }
        return try json(processes)
    }

    static let listSimulators = MCPTool(
        name: "slog_list_simulators",
        description: "List iOS Simulators. Returns JSON array of {name, udid, state, runtime} objects."
    ) { (args: ListSimulatorsArgs) in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        var arguments = ["simctl", "list", "devices", "-j"]
        if args.booted == true {
            arguments.insert("booted", at: 3)
        }
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = jsonObj["devices"] as? [String: [[String: Any]]]
        else {
            return .text("{\"error\": \"Failed to parse simulator list\"}")
        }

        struct SimulatorInfo: Encodable {
            let name: String
            let udid: String
            let state: String
            let runtime: String
        }

        var simulators: [SimulatorInfo] = []

        for (runtime, deviceList) in devices.sorted(by: { $0.key < $1.key }) {
            let runtimeName = runtime
                .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ")

            for device in deviceList {
                guard let name = device["name"] as? String,
                      let udid = device["udid"] as? String,
                      let state = device["state"] as? String
                else { continue }

                if let isAvailable = device["isAvailable"] as? Bool, !isAvailable, args.all != true {
                    continue
                }

                if args.booted == true, state != "Booted" {
                    continue
                }

                simulators.append(SimulatorInfo(
                    name: name, udid: udid, state: state, runtime: runtimeName
                ))
            }
        }

        return try json(simulators)
    }

    static let doctor = MCPTool(
        name: "slog_doctor",
        description: "Check system requirements for slog. Returns JSON object with check results."
    ) {
        struct CheckResult: Encodable {
            let name: String
            let status: String
            let hint: String?
        }

        func checkCommand(_ path: String, arguments: [String]) -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }

        var checks: [CheckResult] = []

        let logExists = FileManager.default.isExecutableFile(atPath: "/usr/bin/log")
        checks.append(CheckResult(
            name: "log CLI",
            status: logExists ? "ok" : "fail",
            hint: logExists ? nil : "The macOS unified logging CLI is missing"
        ))

        let streamOK = checkCommand("/usr/bin/log", arguments: ["stream", "--timeout", "1"])
        checks.append(CheckResult(
            name: "Log stream access",
            status: streamOK ? "ok" : "fail",
            hint: streamOK ? nil : "Grant Full Disk Access to your terminal: System Settings > Privacy & Security > Full Disk Access"
        ))

        let showOK = checkCommand("/usr/bin/log", arguments: ["show", "--last", "1s", "--style", "ndjson"])
        checks.append(CheckResult(
            name: "Log archive access",
            status: showOK ? "ok" : "fail",
            hint: showOK ? nil : "Grant Full Disk Access to your terminal: System Settings > Privacy & Security > Full Disk Access"
        ))

        let simctlExists = FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun")
        let simctlOK = simctlExists && checkCommand("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"])
        checks.append(CheckResult(
            name: "Simulator support",
            status: simctlOK ? "ok" : "fail",
            hint: simctlOK ? nil : "Install Xcode Command Line Tools: xcode-select --install"
        ))

        return try json(checks)
    }

    // MARK: - All Tools

    static let all: [MCPTool] = [
        show,
        stream,
        listProcesses,
        listSimulators,
        doctor,
    ]
}
