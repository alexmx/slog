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
        
        Run `slog <command> --help` for each command's options.
        
        ━━━ EXAMPLES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        
        Basic streaming:
          slog stream --process Finder
          slog stream --process MyApp --level error
          slog stream --subsystem com.myapp.network
        
        iOS Simulator:
          slog stream --simulator --process MyApp
          slog stream --simulator-udid <UDID> --process MyApp
          slog show --simulator --last 5m --process MyApp
        
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
        subcommands: [
            StreamCommand.self,
            ShowCommand.self,
            ListCommand.self,
            ProfileCommand.self,
            DoctorCommand.self,
            MCPCommand.self
        ],
        defaultSubcommand: StreamCommand.self
    )
}
