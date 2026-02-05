# AI Agent Guidelines

This file provides guidance to AI agents when working with code in this repository.

## Project Overview

slog is a Swift CLI tool for intercepting and filtering macOS/iOS logs. It wraps Apple's `log` CLI to provide enhanced filtering, formatting, and iOS Simulator support.

## Build Commands

```bash
swift build              # Debug build
swift build -c release   # Release build
swift run slog [args]    # Run the tool
swift test               # Run all tests
swift package clean      # Clean build artifacts
```

**AI agents:** Always use the **haiku model with a Bash subagent** when running `swift build`, `swift test`, `git commit`, or `git push` to minimize cost and latency.

## CLI Reference

### Stream Command (default)

Stream logs from macOS or iOS Simulator.

**Target Options:**
- `--process <name>` - Filter by process name
- `--pid <id>` - Filter by process ID
- `--simulator` - Stream from iOS Simulator instead of host
- `--simulator-udid <udid>` - Simulator UDID (auto-detects if one booted)

**Filter Options:**
- `--subsystem <name>` - Filter by subsystem (e.g., com.apple.network)
- `--category <name>` - Filter by category
- `--level <level>` - Minimum log level: debug, info, default, error, fault
- `--grep <pattern>` - Filter messages by regex pattern

**Output Options:**
- `--format <fmt>` - Output format: plain, compact, color (default), json, toon
- `--info` - Include info-level messages
- `--debug` - Include debug-level messages

**Timing Options (for bounded capture):**
- `--timeout <duration>` - Max wait for first log (exits with code 1 if exceeded)
- `--capture <duration>` - Capture duration after first log arrives
- `--count <n>` - Number of entries to capture

Duration format: `5s`, `30s`, `2m`, `1h` (seconds assumed if no suffix)

### Show Command

Query historical/persisted logs from the macOS log archive.

**Time Range Options:**
- `--last <duration|boot>` - Show logs from last duration (e.g., 5m, 1h) or boot
- `--start <date>` - Start date (e.g., "2024-01-15 10:30:00")
- `--end <date>` - End date (e.g., "2024-01-15 11:00:00")

**Filter Options:**
- `--process <name>` - Filter by process name
- `--pid <id>` - Filter by process ID
- `--subsystem <name>` - Filter by subsystem (e.g., com.apple.network)
- `--category <name>` - Filter by category
- `--level <level>` - Minimum log level: debug, info, default, error, fault
- `--grep <pattern>` - Filter messages by regex pattern

**Output Options:**
- `--format <fmt>` - Output format: plain, compact, color (default), json, toon
- `--info` - Include info-level messages
- `--debug` - Include debug-level messages
- `--count <n>` - Maximum number of entries to display

**Archive:**
- `[archive-path]` - Optional path to a .logarchive file

Requires at least `--last`, `--start`, or an archive path. `--last` and `--start`/`--end` are mutually exclusive.

### List Command

- `list processes [--filter <name>]` - List running processes
- `list simulators [--booted] [--all]` - List iOS Simulators

### Examples

```bash
# Basic streaming
slog stream --process Finder
slog stream --process MyApp --level error
slog stream --subsystem com.myapp.network

# iOS Simulator
slog stream --simulator --process MyApp

# Bounded capture (for scripts/automation)
slog stream --process MyApp --count 10
slog stream --process MyApp --timeout 30s --capture 10s

# Output formats
slog stream --process MyApp --format compact
slog stream --process MyApp --format json | jq '.message'

# Historical logs
slog show --last 5m
slog show --last 1h --process Finder
slog show --last 30s --level error
slog show --last boot --subsystem com.apple.network
slog show --start "2024-01-15 10:00:00" --end "2024-01-15 11:00:00"
slog show --last 5m --format json | jq '.message'
slog show /path/to/file.logarchive
```

### Exit Codes

- 0: Capture complete or user interrupt
- 1: Timeout (no logs within --timeout) or stream error

## Architecture

```
Sources/slog/
├── Commands/           # CLI commands using ArgumentParser
│   ├── RootCommand.swift    # @main entry point with 3 subcommands
│   ├── StreamCommand.swift  # Main log streaming with filters
│   ├── ShowCommand.swift    # Historical log queries
│   └── ListCommand.swift    # List processes/simulators
├── Core/               # Log handling
│   ├── LogEntry.swift       # LogEntry struct, LogLevel enum
│   ├── LogParser.swift      # NDJSON and legacy format parser
│   ├── LogStreamer.swift    # Stream process management, PredicateBuilder
│   ├── LogReader.swift      # Historical log reading via `log show`
│   └── DurationParser.swift # Duration string parsing (e.g., "5s", "2m")
├── Filters/            # Filtering system
│   ├── FilterChain.swift    # Thread-safe filter chain with DSL
│   └── Predicates.swift     # 10+ predicate types (composable)
└── Output/             # Formatters
    ├── Formatter.swift      # Protocol, registry, OutputFormat enum
    └── *Formatter.swift     # Plain, Color, JSON, Toon implementations
```

**Key patterns:**
- Protocol-based extensibility (LogFormatter, LogPredicate)
- Builder pattern for predicates and filter chains
- Modern Swift Concurrency (async/await, actors, Sendable types)
- swift-subprocess for async process execution

## Log Levels

Ordered from most to least verbose: debug (0), info (1), default (2), error (16), fault (17)

**Auto-debug behavior:** When filtering by `--subsystem`, debug logs are automatically included. Override with explicit `--level` flag.

## Output Formats

- `plain` - Full details: timestamp, level, process, subsystem, message
- `compact` - Minimal: timestamp, level, message only
- `color` - Same as plain with ANSI colors based on log level (default)
- `json` - JSON output for piping to other tools
- `toon` - TOON output (token-optimized for LLMs)

## Testing

Uses Apple's Testing framework (not XCTest):
- `@Suite` for test groups, `@Test` for tests, `#expect()` for assertions
- Tests in `Tests/slogTests/`

```bash
swift test                    # Run all tests
swift test --filter <name>    # Run specific test
```

## Dependencies

- `swift-argument-parser` - CLI parsing and command structure
- `swift-subprocess` - Modern async process execution
- `Rainbow` - ANSI color support for terminal output
- `ToonFormat` - TOON (Token-Oriented Object Notation) encoding

## Git Commits

**Never add `Co-Authored-By` attribution to commits.** Write commit messages without any co-author trailers.
