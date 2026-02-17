//
//  RootCommand.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import ArgumentParser

/// Root command for slog CLI
@main
struct Slog: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slog",
        abstract: "Swift CLI tool for intercepting and filtering macOS/iOS logs",
        discussion: """
        slog wraps Apple's `log` CLI to provide enhanced filtering, \
        formatting, and iOS Simulator support.

        ━━━ STREAM COMMAND ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        Stream logs from macOS or iOS Simulator (default command).

        Target Options:
          --process <name>        Filter by process name
          --pid <id>              Filter by process ID
          --simulator             Stream from iOS Simulator instead of host
          --simulator-udid <udid> Simulator UDID (auto-detects if one booted)

        Filter Options:
          --subsystem <name>      Filter by subsystem (e.g., com.apple.network)
          --category <name>       Filter by category
          --level <level>         Minimum log level: debug, info, default, error, fault
          --grep <pattern>        Filter messages by regex pattern

        Output Options:
          --format <fmt>          Output format: plain, compact, color (default), json, toon
          --info                  Include info-level messages
          --debug                 Include debug-level messages

        Timing Options (for bounded capture):
          --timeout <duration>    Max wait for first log (exits with code 1 if exceeded)
          --capture <duration>    Capture duration after first log arrives
          --count <n>             Number of entries to capture

          Duration format: 5s, 30s, 2m, 1h (seconds assumed if no suffix)

        ━━━ SHOW COMMAND ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        Query historical/persisted logs from the macOS log archive.

        Time Range Options:
          --last <duration|boot>  Show logs from last duration (e.g., 5m, 1h) or boot
          --start <date>          Start date (e.g., "2024-01-15 10:30:00")
          --end <date>            End date (e.g., "2024-01-15 11:00:00")

        Filter Options:
          --process <name>        Filter by process name
          --pid <id>              Filter by process ID
          --subsystem <name>      Filter by subsystem
          --category <name>       Filter by category
          --level <level>         Minimum log level: debug, info, default, error, fault
          --grep <pattern>        Filter messages by regex pattern

        Output Options:
          --format <fmt>          Output format: plain, compact, color (default), json, toon
          --info                  Include info-level messages
          --debug                 Include debug-level messages
          --count <n>             Maximum number of entries to display

        Archive:
          [archive-path]          Optional path to a .logarchive file

        ━━━ LIST COMMAND ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        List available processes or simulators.

        Subcommands:
          list processes          List running processes
            --filter <name>       Filter by name (case-insensitive)

          list simulators         List iOS Simulators
            --booted              Show only booted simulators
            --all                 Include unavailable simulators

        ━━━ EXAMPLES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        Basic streaming:
          slog stream --process Finder
          slog stream --process MyApp --level error
          slog stream --subsystem com.myapp.network

        iOS Simulator:
          slog stream --simulator --process MyApp
          slog stream --simulator-udid <UDID> --process MyApp

        Bounded capture (for scripts/automation):
          slog stream --process MyApp --count 10
          slog stream --process MyApp --timeout 30s --capture 10s
          slog stream --process MyApp --timeout 1m --count 50

        Output formats:
          slog stream --process MyApp --format compact
          slog stream --process MyApp --format json | jq '.message'

        Historical logs:
          slog show --last 5m
          slog show --last 1h --process Finder
          slog show --last 30s --level error
          slog show --last boot --subsystem com.apple.network
          slog show --start "2024-01-15 10:00:00" --end "2024-01-15 11:00:00"
          slog show --last 5m --format json | jq '.message'
          slog show /path/to/file.logarchive

        Profiles:
          slog profile create myapp --process MyApp --subsystem com.myapp --level debug
          slog stream --profile myapp
          slog stream --profile myapp --level error
          slog profile list
          slog profile show myapp
          slog profile delete myapp

        Discovery:
          slog list processes --filter finder
          slog list simulators --booted
        """,
        version: slogVersion,
        subcommands: [StreamCommand.self, ShowCommand.self, ListCommand.self, ProfileCommand.self, DoctorCommand.self],
        defaultSubcommand: StreamCommand.self
    )
}
