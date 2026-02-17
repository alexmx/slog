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
        let processes = try SystemQuery.listProcesses(filter: filter)

        print("Available processes:\n")
        for p in processes {
            print("  \(p.name) (PID: \(p.pid))")
        }
        print("\nTotal: \(processes.count) processes")
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
        let simulators = try SystemQuery.listSimulators(booted: booted, all: all)

        print("Available simulators:\n")

        if simulators.isEmpty {
            if booted {
                print("  No booted simulators found.")
                print("  Boot a simulator with: xcrun simctl boot <UDID>")
            } else {
                print("  No simulators found.")
                print("  Create a simulator in Xcode or with: xcrun simctl create")
            }
            return
        }

        // Group by runtime for display
        var currentRuntime = ""
        for sim in simulators {
            if sim.runtime != currentRuntime {
                if !currentRuntime.isEmpty { print("") }
                currentRuntime = sim.runtime
                print("  \(sim.runtime):")
            }
            let stateIndicator = sim.state == "Booted" ? " [BOOTED]" : ""
            print("    \(sim.name)\(stateIndicator)")
            print("      UDID: \(sim.udid)")
        }

        print("\nTotal: \(simulators.count) simulators")
    }
}
