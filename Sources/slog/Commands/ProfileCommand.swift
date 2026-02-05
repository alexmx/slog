//
//  ProfileCommand.swift
//  slog
//

import ArgumentParser
import Foundation

/// Manage saved filter/format profiles
struct ProfileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profile",
        abstract: "Manage saved filter/format profiles",
        subcommands: [
            ListProfiles.self,
            ShowProfile.self,
            CreateProfile.self,
            DeleteProfile.self,
        ]
    )
}

// MARK: - List

struct ListProfiles: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available profiles"
    )

    func run() throws {
        let profiles = try ProfileManager.list()

        if profiles.isEmpty {
            print("No profiles found.")
            print("Create one with: slog profile create <name> [options]")
            print("Profiles directory: \(XDGDirectories.profilesDirectory.path)")
        } else {
            for name in profiles {
                print(name)
            }
        }
    }
}

// MARK: - Show

struct ShowProfile: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a profile's contents"
    )

    @Argument(help: "Profile name")
    var name: String

    func run() throws {
        let profile = try ProfileManager.load(name)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)

        guard let json = String(data: data, encoding: .utf8) else {
            throw ProfileError.invalidProfile("Could not encode profile")
        }

        print(json)
    }
}

// MARK: - Create

struct CreateProfile: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a profile from CLI options"
    )

    @Argument(help: "Profile name")
    var name: String

    @Flag(name: .long, help: "Overwrite existing profile")
    var force = false

    // MARK: - Filter Options

    @Option(name: .long, help: "Filter by process name")
    var process: String?

    @Option(name: .long, help: "Filter by process ID")
    var pid: Int?

    @Option(name: .long, help: "Filter by subsystem")
    var subsystem: String?

    @Option(name: .long, help: "Filter by category")
    var category: String?

    @Option(name: .long, help: "Minimum log level (debug, info, default, error, fault)")
    var level: LogLevel?

    @Option(name: .long, help: "Filter messages by regex pattern")
    var grep: String?

    // MARK: - Output Options

    @Option(name: .long, help: "Output format (plain, compact, color, json, toon)")
    var format: OutputFormat?

    @Option(name: .long, help: "Timestamp mode (absolute, relative)")
    var time: TimeMode?

    @Flag(name: .long, help: "Include info-level messages")
    var info = false

    @Flag(name: .long, help: "Include debug-level messages")
    var debug = false

    @Flag(name: .long, help: "Include source location info")
    var source = false

    @Flag(name: .long, help: "Collapse consecutive identical messages")
    var dedup = false

    // MARK: - Stream Options

    @Flag(name: .long, help: "Stream from iOS Simulator")
    var simulator = false

    @Option(name: .long, help: "Simulator UDID")
    var simulatorUDID: String?

    func run() throws {
        let profile = Profile(
            process: process,
            pid: pid,
            subsystem: subsystem,
            category: category,
            level: level?.rawValue.lowercased(),
            grep: grep,
            format: format?.rawValue,
            time: time?.rawValue,
            info: info ? true : nil,
            debug: debug ? true : nil,
            source: source ? true : nil,
            dedup: dedup ? true : nil,
            simulator: simulator ? true : nil,
            simulatorUDID: simulatorUDID
        )

        guard !profile.isEmpty else {
            throw ValidationError("No options specified. Provide at least one filter or format option.")
        }

        try ProfileManager.save(name, profile: profile, force: force)
        print("Profile '\(name)' saved to \(ProfileManager.profileURL(name).path)")
    }
}

// MARK: - Delete

struct DeleteProfile: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a profile"
    )

    @Argument(help: "Profile name")
    var name: String

    func run() throws {
        try ProfileManager.delete(name)
        print("Profile '\(name)' deleted.")
    }
}
