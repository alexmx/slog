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
            description: "Stream and filter macOS/iOS logs — query historical logs, stream live output, and filter by process, subsystem, level, or regex. Workflow: slog_list_processes to find process names, then slog_show for recent/historical logs or slog_stream for live capture. Start with broad filters (process only), then narrow with subsystem/level/grep.",
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
