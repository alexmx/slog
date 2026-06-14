//
//  MCPCommand.swift
//  slog
//

import ArgumentParser
import Foundation
import SwiftMCP

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start an MCP server for AI tool integration"
    )

    @Flag(help: "Print setup instructions for popular AI coding agents")
    var setup = false

    func run() async {
        if setup {
            printSetup()
            return
        }

        let server = MCPServer(
            name: "slog",
            version: slogVersion,
            description: """
            Stream and filter macOS/iOS unified logs.
            
            Workflow: (1) discover targets with `slog_list_processes` / \
            `slog_list_simulators`; (2) for past events use `slog_show` with a time range, \
            for live debugging use `slog_stream` with a bounded `count`. Start broad \
            (process only), then narrow with subsystem/level/grep.
            
            Custom-subsystem debug events do not persist by default — `slog_show` cannot \
            replay them, so reach for `slog_stream` when chasing debug-level output from \
            your own app.
            """,
            tools: SlogTools.all
        )
        await server.run()
    }

    private func printSetup() {
        print("""
        Add slog as an MCP server to your AI coding agent:
        
          Claude Code:          claude mcp add --transport stdio slog -- slog mcp
          Codex CLI:            codex mcp add slog -- slog mcp
          VS Code / Copilot:    code --add-mcp '{"name":"slog","command":"slog","args":["mcp"]}'
          Cursor:               cursor --add-mcp '{"name":"slog","command":"slog","args":["mcp"]}'
        """)
    }
}
