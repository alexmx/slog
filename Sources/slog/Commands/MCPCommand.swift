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
            description: "Intercept and filter macOS/iOS logs. Query historical logs with slog_show, stream live logs with slog_stream, discover processes with slog_list_processes, list simulators with slog_list_simulators, and check system requirements with slog_doctor.",
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
