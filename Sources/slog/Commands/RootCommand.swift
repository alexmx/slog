//
//  RootCommand.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import ArgumentParser

/// Root command for slog CLI
@main
struct Slog: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slog",
        abstract: "Swift CLI tool for intercepting and filtering macOS/iOS logs",
        discussion: """
            slog wraps Apple's `log` CLI to provide enhanced filtering, \
            formatting, and iOS Simulator support.

            Examples:
              slog stream --process Finder
              slog stream --process MyApp --level error
              slog stream --simulator --process MyApp
              slog list processes
              slog list simulators
            """,
        version: "1.0.0",
        subcommands: [StreamCommand.self, ListCommand.self],
        defaultSubcommand: StreamCommand.self
    )
}
