//
//  StreamCommand.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import ArgumentParser
import Darwin
import Foundation

/// Command for streaming logs
struct StreamCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stream",
        abstract: "Stream logs from macOS or iOS Simulator"
    )

    // MARK: - Target Options

    @Option(name: .long, help: "Filter by process name")
    var process: String?

    @Option(name: .long, help: "Filter by process ID")
    var pid: Int?

    @Flag(name: .long, help: "Stream from iOS Simulator instead of host")
    var simulator = false

    @Option(name: .long, help: "Simulator UDID (auto-detects if only one booted)")
    var simulatorUDID: String?

    // MARK: - Filter Options

    @Option(name: .long, help: "Filter by subsystem (e.g., com.apple.network)")
    var subsystem: String?

    @Option(name: .long, help: "Filter by category")
    var category: String?

    @Option(name: .long, help: "Minimum log level (debug, info, default, error, fault)")
    var level: String?

    @Option(name: .long, help: "Filter messages by regex pattern")
    var grep: String?

    // MARK: - Output Options

    @Option(name: .long, help: "Output format (plain, color, json)")
    var format: String = "color"

    @Flag(name: .long, help: "Include info-level messages")
    var info = false

    @Flag(name: .long, help: "Include debug-level messages")
    var debug = false

    // MARK: - Run

    func run() throws {
        // Determine output format
        let outputFormat = OutputFormat(rawValue: format) ?? .color
        let formatter = FormatterRegistry.formatter(for: outputFormat)

        // Build server-side predicate
        let predicate = PredicateBuilder.from(
            process: process,
            pid: pid,
            subsystem: subsystem,
            category: category,
            level: level.flatMap { LogLevel(string: $0) }
        )

        // Build client-side filter chain for regex
        let filterChain = FilterChain()
        if let grepPattern = grep {
            filterChain.filterByMessageRegex(grepPattern)
        }

        // Determine target
        let target: StreamConfiguration.Target
        if simulator {
            let udid = try resolveSimulatorUDID()
            target = .simulator(udid: udid)
        } else {
            target = .local
        }

        // Create configuration
        let config = StreamConfiguration(
            target: target,
            predicate: predicate,
            includeInfo: info || debug,
            includeDebug: debug
        )

        // Create streamer
        let streamer = LogStreamer()

        // Set up signal handling for graceful shutdown
        setupSignalHandler(streamer: streamer)

        // Set up callbacks
        streamer.onEntry = { entry in
            // Apply client-side filters
            if filterChain.isEmpty || filterChain.matches(entry) {
                let output = formatter.format(entry)
                print(output)
            }
        }

        streamer.onError = { error in
            FileHandle.standardError.write(
                "Error: \(error.localizedDescription)\n".data(using: .utf8)!
            )
        }

        // Start streaming
        try streamer.start(configuration: config)

        // Keep running until interrupted
        RunLoop.current.run()
    }

    // MARK: - Helpers

    private func resolveSimulatorUDID() throws -> String {
        if let udid = simulatorUDID {
            return udid
        }

        // Auto-detect booted simulator
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "booted", "-j"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else {
            throw StreamerError.simulatorNotFound("Could not parse simulator list")
        }

        // Find first booted device
        for (_, deviceList) in devices {
            for device in deviceList {
                if let state = device["state"] as? String, state == "Booted",
                   let udid = device["udid"] as? String {
                    return udid
                }
            }
        }

        throw StreamerError.simulatorNotFound("No booted simulator found. Boot a simulator or specify --simulator-udid")
    }

    private func setupSignalHandler(streamer: LogStreamer) {
        signal(SIGINT) { _ in
            Darwin.exit(0)
        }

        signal(SIGTERM) { _ in
            Darwin.exit(0)
        }
    }
}
