//
//  ListCommand.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import ArgumentParser
import Foundation

/// Command for listing available targets
struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available processes or simulators",
        subcommands: [ListProcesses.self, ListSimulators.self]
    )
}

// MARK: - List Processes

struct ListProcesses: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "processes",
        abstract: "List running processes"
    )

    @Option(name: .long, help: "Filter processes by name (case-insensitive)")
    var filter: String?

    func run() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,comm"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            print("Failed to read process list")
            return
        }

        let lines = output.split(separator: "\n").dropFirst() // Skip header

        var processes: [(pid: Int, name: String)] = []

        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2,
                  let pid = Int(parts[0]) else { continue }

            let name = String(parts[1])
            let processName = URL(fileURLWithPath: name).lastPathComponent

            // Apply filter if specified
            if let filter = filter?.lowercased() {
                guard processName.lowercased().contains(filter) else { continue }
            }

            processes.append((pid: pid, name: processName))
        }

        // Sort by name
        processes.sort { $0.name.lowercased() < $1.name.lowercased() }

        // Remove duplicates (same name)
        var seen = Set<String>()
        let unique = processes.filter { seen.insert($0.name).inserted }

        // Print results
        print("Available processes:\n")
        for process in unique {
            print("  \(process.name) (PID: \(process.pid))")
        }
        print("\nTotal: \(unique.count) processes")
    }
}

// MARK: - List Simulators

struct ListSimulators: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "simulators",
        abstract: "List iOS Simulators"
    )

    @Flag(name: .long, help: "Show only booted simulators")
    var booted = false

    @Flag(name: .long, help: "Show all simulators (including unavailable)")
    var all = false

    func run() throws {
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
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else {
            print("Failed to parse simulator list")
            return
        }

        print("Available simulators:\n")

        var totalCount = 0

        for (runtime, deviceList) in devices.sorted(by: { $0.key < $1.key }) {
            // Extract readable runtime name
            let runtimeName = runtime
                .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: ".", with: " ")

            var printedRuntime = false

            for device in deviceList {
                guard let name = device["name"] as? String,
                      let udid = device["udid"] as? String,
                      let state = device["state"] as? String else { continue }

                // Skip unavailable unless --all
                if let isAvailable = device["isAvailable"] as? Bool, !isAvailable, !all {
                    continue
                }

                // Skip non-booted if --booted flag
                if booted && state != "Booted" {
                    continue
                }

                if !printedRuntime {
                    print("  \(runtimeName):")
                    printedRuntime = true
                }

                let stateIndicator = state == "Booted" ? " [BOOTED]" : ""
                print("    \(name)\(stateIndicator)")
                print("      UDID: \(udid)")

                totalCount += 1
            }

            if printedRuntime {
                print("")
            }
        }

        if totalCount == 0 {
            if booted {
                print("  No booted simulators found.")
                print("  Boot a simulator with: xcrun simctl boot <UDID>")
            } else {
                print("  No simulators found.")
                print("  Create a simulator in Xcode or with: xcrun simctl create")
            }
        } else {
            print("Total: \(totalCount) simulators")
        }
    }
}
