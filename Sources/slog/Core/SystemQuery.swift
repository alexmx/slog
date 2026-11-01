//
//  SystemQuery.swift
//  slog
//

import Foundation

/// A running macOS process
public struct RunningProcess: Codable, Sendable {
    public let name: String
    public let pid: Int
}

/// An iOS Simulator device
public struct SimulatorInfo: Codable, Sendable {
    public let name: String
    public let udid: String
    public let state: String
    public let runtime: String
}

/// Shared service for querying system state (processes, simulators)
public enum SystemQuery {
    /// List running macOS processes, optionally filtered by name substring
    public static func listProcesses(filter: String? = nil) throws -> [RunningProcess] {
        let data = try runTool("/bin/ps", ["-axo", "pid,comm"])
        guard let output = String(data: data, encoding: .utf8) else {
            throw SystemQueryError.parseError("Failed to read process list")
        }
        return parseProcesses(output, filter: filter)
    }

    /// List iOS Simulators
    public static func listSimulators(booted: Bool = false, all: Bool = false) throws -> [SimulatorInfo] {
        var arguments = ["simctl", "list", "devices"]
        if booted {
            arguments.append("booted")
        }
        arguments.append("-j")
        return try parseSimulators(runTool("/usr/bin/xcrun", arguments), booted: booted, all: all)
    }

    /// Return `udid` if given, otherwise the UDID of the one booted simulator.
    /// Throws when none, or more than one, is booted.
    public static func resolveSimulatorUDID(_ udid: String? = nil) throws -> String {
        if let udid {
            return udid
        }
        return try bootedUDID(from: listSimulators(booted: true, all: true))
    }

    // MARK: - Parsing

    /// Parse `ps -axo pid,comm` output into processes, one per name, sorted by name.
    static func parseProcesses(_ output: String, filter: String?) -> [RunningProcess] {
        let filter = filter?.lowercased()
        var processes: [RunningProcess] = []
        var seen = Set<String>()

        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }

            let name = URL(fileURLWithPath: String(parts[1])).lastPathComponent
            if let filter, !name.lowercased().contains(filter) {
                continue
            }
            if seen.insert(name).inserted {
                processes.append(RunningProcess(name: name, pid: pid))
            }
        }

        return processes.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// `xcrun simctl list devices -j` output. Device fields are optional so one
    /// odd entry is skipped rather than failing the whole list.
    private struct DeviceList: Decodable {
        struct Device: Decodable {
            let name: String?
            let udid: String?
            let state: String?
            let isAvailable: Bool?
        }

        let devices: [String: [Device]]
    }

    /// Parse simctl's device JSON, ordered by runtime identifier.
    static func parseSimulators(_ data: Data, booted: Bool, all: Bool) throws -> [SimulatorInfo] {
        let list: DeviceList
        do {
            list = try JSONDecoder().decode(DeviceList.self, from: data)
        } catch {
            throw SystemQueryError.parseError("Failed to parse simulator list")
        }

        return list.devices.sorted { $0.key < $1.key }.flatMap { runtime, devices in
            devices.compactMap { device -> SimulatorInfo? in
                guard let name = device.name, let udid = device.udid, let state = device.state else { return nil }
                if device.isAvailable == false, !all {
                    return nil
                }
                if booted, state != "Booted" {
                    return nil
                }
                return SimulatorInfo(name: name, udid: udid, state: state, runtime: runtimeName(runtime))
            }
        }
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-18-2` → `iOS 18 2`
    private static func runtimeName(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
    }

    /// The UDID of the single booted simulator in `simulators`.
    static func bootedUDID(from simulators: [SimulatorInfo]) throws -> String {
        let booted = simulators.filter { $0.state == "Booted" }
        switch booted.count {
        case 1:
            return booted[0].udid
        case 0:
            throw SystemQueryError.noBootedSimulator
        default:
            throw SystemQueryError.multipleBootedSimulators(booted)
        }
    }

    // MARK: - Process

    /// Run a tool to completion and return its standard output.
    private static func runTool(_ path: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let command = ([path] + arguments).joined(separator: " ")
            throw SystemQueryError.commandFailed(command: command, exitCode: process.terminationStatus)
        }
        return data
    }
}

public enum SystemQueryError: Error, LocalizedError {
    case parseError(String)
    case commandFailed(command: String, exitCode: Int32)
    case noBootedSimulator
    case multipleBootedSimulators([SimulatorInfo])

    public var errorDescription: String? {
        switch self {
        case .parseError(let message):
            "System query error: \(message)"
        case .commandFailed(let command, let exitCode):
            "`\(command)` exited with code \(exitCode)"
        case .noBootedSimulator:
            "No booted simulator found. Boot one, or pass its UDID (--simulator-udid / simulator_udid)."
        case .multipleBootedSimulators(let simulators):
            """
            Multiple simulators are booted; pass a UDID (--simulator-udid / simulator_udid):
            \(simulators.map { "  \($0.name) (\($0.udid))" }.joined(separator: "\n"))
            """
        }
    }
}
