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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,comm"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            throw SystemQueryError.parseError("Failed to read process list")
        }

        let lines = output.split(separator: "\n").dropFirst()
        var processes: [RunningProcess] = []
        var seen = Set<String>()

        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }

            let name = URL(fileURLWithPath: String(parts[1])).lastPathComponent

            if let filter = filter?.lowercased() {
                guard name.lowercased().contains(filter) else { continue }
            }

            if seen.insert(name).inserted {
                processes.append(RunningProcess(name: name, pid: pid))
            }
        }

        processes.sort { $0.name.lowercased() < $1.name.lowercased() }
        return processes
    }

    /// List iOS Simulators
    public static func listSimulators(booted: Bool = false, all: Bool = false) throws -> [SimulatorInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        var arguments = ["simctl", "list", "devices", "-j"]
        if booted {
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
            throw SystemQueryError.parseError("Failed to parse simulator list")
        }

        var simulators: [SimulatorInfo] = []

        for (runtime, deviceList) in devices.sorted(by: { $0.key < $1.key }) {
            let runtimeName = runtime
                .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: ".", with: " ")

            for device in deviceList {
                guard let name = device["name"] as? String,
                      let udid = device["udid"] as? String,
                      let state = device["state"] as? String
                else { continue }

                if let isAvailable = device["isAvailable"] as? Bool, !isAvailable, !all {
                    continue
                }

                if booted, state != "Booted" {
                    continue
                }

                simulators.append(SimulatorInfo(
                    name: name, udid: udid, state: state, runtime: runtimeName
                ))
            }
        }

        return simulators
    }

    /// Auto-detect a booted simulator UDID, or return the provided one
    public static func resolveSimulatorUDID(_ udid: String? = nil) throws -> String {
        if let udid {
            return udid
        }

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
            throw StreamError.simulatorNotFound("Could not parse simulator list")
        }

        for (_, deviceList) in devices {
            for device in deviceList {
                if let state = device["state"] as? String, state == "Booted",
                   let udid = device["udid"] as? String
                {
                    return udid
                }
            }
        }

        throw StreamError.simulatorNotFound(
            "No booted simulator found. Boot a simulator or specify --simulator-udid"
        )
    }
}

public enum SystemQueryError: Error, LocalizedError {
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .parseError(let message):
            "System query error: \(message)"
        }
    }
}
