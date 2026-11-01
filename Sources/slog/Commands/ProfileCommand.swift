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
            DeleteProfile.self
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

        print(String(decoding: data, as: UTF8.self))
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

    @OptionGroup(title: "Filter Options")
    var filter: FilterOptions

    @OptionGroup(title: "Output Options")
    var output: OutputOptions

    @OptionGroup(title: "Simulator Options")
    var simulatorOptions: SimulatorOptions

    func run() throws {
        let profile = makeProfile()

        guard !profile.isEmpty else {
            throw ValidationError("No options specified. Provide at least one filter or format option.")
        }

        try ProfileManager.save(name, profile: profile, force: force)
        print("Profile '\(name)' saved to \(ProfileManager.profileURL(name).path)")
    }

    /// The profile these options describe. Unset options stay `nil`, so loading
    /// the profile only overrides what was given here.
    func makeProfile() -> Profile {
        Profile(
            process: filter.process,
            pid: filter.pid,
            subsystem: filter.subsystem,
            category: filter.category,
            level: filter.level?.rawValue.lowercased(),
            grep: filter.grep,
            excludeGrep: filter.excludeGrep,
            format: output.format?.rawValue,
            time: output.time?.rawValue,
            info: output.info,
            debug: output.debug,
            source: output.source,
            dedup: output.dedup,
            simulator: simulatorOptions.simulator ? true : nil,
            simulatorUDID: simulatorOptions.simulatorUDID
        )
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
