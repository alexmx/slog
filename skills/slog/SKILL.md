---
name: slog
description: Guide for using the slog CLI tool to stream, query, and filter macOS/iOS logs. Use when the user asks how to use slog, needs help building slog commands, wants to filter logs, stream from simulators, or work with log archives.
user-invocable: false
---

# slog CLI Usage Guide

slog is a Swift CLI tool for intercepting and filtering macOS/iOS logs. It wraps Apple's `log` CLI to provide enhanced filtering, formatting, and iOS Simulator support.

Help the user construct the right slog command for their needs.

## Commands

slog has six commands: `stream` (default), `show`, `profile`, `list`, `doctor`, and `mcp`.

## Stream (default)

Stream live logs from macOS or an iOS Simulator.

```
slog stream [options]
```

**Target:**
- `--process <name>` — filter by process name
- `--pid <id>` — filter by process ID
- `--simulator` — stream from iOS Simulator
- `--simulator-udid <udid>` — specific Simulator UDID (auto-detects if one is booted)

**Filters:**
- `--subsystem <name>` — e.g. `com.apple.network`
- `--category <name>` — filter by category
- `--level <level>` — minimum level: `debug`, `info`, `default`, `error`, `fault`
- `--grep <pattern>` — regex filter on message content
- `--exclude-grep <pattern>` — exclude messages matching regex

**Output:**
- `--format <fmt>` — `plain`, `compact`, `color` (default), `json`, `toon`
- `--time <mode>` — timestamp mode: `absolute` (default), `relative`
- `--info` / `--no-info` — include info-level messages
- `--debug` / `--no-debug` — include debug-level messages
- `--source` / `--no-source` — include source location info
- `--dedup` / `--no-dedup` — collapse consecutive identical messages

**Bounded capture (for scripts/automation):**
- `--timeout <duration>` — max wait for first log (exits code 1 if exceeded)
- `--capture <duration>` — capture duration after first log arrives
- `--count <n>` — number of entries to capture

Duration format: `5s`, `30s`, `2m`, `1h` (seconds assumed if no suffix).

### Stream Examples

```bash
slog stream --process Finder
slog stream --process MyApp --level error
slog stream --subsystem com.myapp.network
slog stream --simulator --process MyApp
slog stream --process MyApp --count 10
slog stream --process MyApp --timeout 30s --capture 10s
slog stream --process MyApp --format json | jq '.message'
slog stream --process MyApp --exclude-grep heartbeat
slog stream --process MyApp --dedup
```

## Show

Query historical/persisted logs from the macOS log archive.

```
slog show [options] [archive-path]
```

**Time range (at least one required unless archive-path given):**
- `--last <duration|boot>` — e.g. `5m`, `1h`, `boot`
- `--start <date>` — e.g. `"2024-01-15 10:30:00"`
- `--end <date>` — e.g. `"2024-01-15 11:00:00"`

`--last` and `--start`/`--end` are mutually exclusive.

**Filters:** same as stream (`--process`, `--pid`, `--subsystem`, `--category`, `--level`, `--grep`, `--exclude-grep`).

**Output:** same as stream (`--format`, `--time`, `--info`, `--debug`, `--source`, `--dedup`, `--count`).

### Show Examples

```bash
slog show --last 5m
slog show --last 1h --process Finder
slog show --last 30s --level error
slog show --last boot --subsystem com.apple.network
slog show --start "2024-01-15 10:00:00" --end "2024-01-15 11:00:00"
slog show --last 5m --format json | jq '.message'
slog show /path/to/file.logarchive
slog show --last 5m --grep "api.*users" --exclude-grep health
```

## Profile

Manage saved filter/format profiles. Stored as JSON in `$XDG_CONFIG_HOME/slog/profiles/` (defaults to `~/.config/slog/profiles/`).

```bash
slog profile create <name> [options]   # Create from CLI flags (--force to overwrite)
slog profile list                      # List profiles
slog profile show <name>               # Show profile contents
slog profile delete <name>             # Delete a profile
```

Use with `--profile <name>` on `stream` or `show`. CLI args override profile values. Use `--no-info`, `--no-debug`, `--no-source` to explicitly disable profile flags.

### Profile Examples

```bash
slog profile create myapp --process MyApp --subsystem com.myapp --level debug --format compact
slog stream --profile myapp
slog stream --profile myapp --level error --format json
```

## List

```bash
slog list processes [--filter <name>]     # List running processes
slog list simulators [--booted] [--all]   # List iOS Simulators
```

## Doctor

Check system requirements and diagnose issues.

```bash
slog doctor
```

Checks: log CLI, stream access, log archive access, simulator support (xcrun simctl), profiles directory.

## MCP

Start an MCP (Model Context Protocol) server for AI tool integration.

```bash
slog mcp            # Start MCP server (stdio transport)
slog mcp --setup    # Print integration instructions for Claude Code, VS Code, Cursor, etc.
```

Exposes 5 tools: `slog_show`, `slog_stream`, `slog_list_processes`, `slog_list_simulators`, `slog_doctor`.

## Key Behaviors

- **Auto-debug**: When filtering by `--subsystem`, debug logs are automatically included. Override with explicit `--level`.
- **Log levels** (most to least verbose): `debug` (0), `info` (1), `default` (2), `error` (16), `fault` (17).
- **Exit codes**: 0 = capture complete or user interrupt; 1 = timeout or stream error.

## Output Formats

| Format | Description |
|--------|-------------|
| `plain` | Full: timestamp, level, process, subsystem, message |
| `compact` | Minimal: timestamp, level, message |
| `color` | Same as plain with ANSI colors (default) |
| `json` | JSON output for piping to other tools |
| `toon` | Token-optimized for LLMs |
