# slog

A fast, modern Swift CLI for streaming and filtering macOS and iOS Simulator logs.

slog wraps Apple's `log` CLI to provide enhanced filtering, multiple output formats, saved profiles, and time-bounded capture for automation workflows.

## Features

- **Stream & query logs** from macOS or iOS Simulator in real-time or from history
- **Powerful filtering** by process, subsystem, category, log level, and regex patterns
- **Multiple output formats**: plain, compact, colored, JSON, and TOON (token-optimized for LLMs)
- **Saved profiles** for reusable filter/format combinations
- **Time-bounded capture** with `--timeout`, `--capture`, and `--count` for scripting
- **Auto-detection** of booted iOS Simulators
- **MCP server** for AI agent integration with 5 tools
- **Modern Swift** built with async/await and Swift Concurrency

## Installation

### Homebrew

```bash
brew tap alexmx/tools
brew install slog
```

### From Source

Requires Swift 6.2+ and macOS 26+.

```bash
git clone https://github.com/alexmx/slog.git
cd slog
swift build -c release
cp .build/release/slog /usr/local/bin/
```

## Quick Start

```bash
# Stream all logs from Finder
slog stream --process Finder

# Stream errors only from your app
slog stream --process MyApp --level error

# Stream from iOS Simulator
slog stream --simulator --process MyApp

# Query last 5 minutes of logs
slog show --last 5m --process MyApp

# Capture 10 log entries and exit
slog stream --process MyApp --count 10
```

## Command Reference

### Streaming & Querying

| Command | Description | Key Options | Example |
|---------|-------------|-------------|---------|
| `stream` | Stream live logs (default command) | `--process` `--subsystem` `--level` `--grep` `--format` `--count` | `slog stream --process MyApp --level error` |
| `show` | Query historical logs | `--last` `--start`/`--end` `--process` `--format` `--count` | `slog show --last 5m --format json` |

### Configuration

| Command | Description | Key Options | Example |
|---------|-------------|-------------|---------|
| `profile create` | Save a filter/format profile | `--process` `--subsystem` `--level` `--format` `--force` | `slog profile create myapp --process MyApp` |
| `profile list` | List saved profiles | | `slog profile list` |
| `profile show` | Show profile contents | | `slog profile show myapp` |
| `profile delete` | Delete a profile | | `slog profile delete myapp` |

### Discovery

| Command | Description | Key Options | Example |
|---------|-------------|-------------|---------|
| `list processes` | List running processes | `--filter <name>` | `slog list processes --filter finder` |
| `list simulators` | List iOS Simulators | `--booted` `--all` | `slog list simulators --booted` |

### System

| Command | Description | Key Options | Example |
|---------|-------------|-------------|---------|
| `doctor` | Check system requirements | | `slog doctor` |
| `mcp` | Start MCP server | `--setup` | `slog mcp --setup` |

## Filtering

### Target Options

| Option | Description |
|--------|-------------|
| `--process <name>` | Filter by process name |
| `--pid <id>` | Filter by process ID |
| `--simulator` | Stream from iOS Simulator instead of macOS |
| `--simulator-udid <udid>` | Specific simulator UDID (auto-detects if omitted) |

### Filter Options

| Option | Description |
|--------|-------------|
| `--subsystem <name>` | Filter by subsystem (e.g., `com.apple.network`) |
| `--category <name>` | Filter by category |
| `--level <level>` | Minimum log level: `debug`, `info`, `default`, `error`, `fault` |
| `--grep <pattern>` | Filter messages by regex pattern |
| `--exclude-grep <pattern>` | Exclude messages matching regex pattern |

### Output Options

| Option | Description |
|--------|-------------|
| `--format <fmt>` | Output format: `plain`, `compact`, `color` (default), `json`, `toon` |
| `--time <mode>` | Timestamp mode: `absolute` (default), `relative` |
| `--info` / `--no-info` | Include info-level messages |
| `--debug` / `--no-debug` | Include debug-level messages |
| `--source` / `--no-source` | Include source location info |
| `--dedup` / `--no-dedup` | Collapse consecutive identical messages |

### Timing Options

For scripting and automation workflows:

| Option | Description |
|--------|-------------|
| `--timeout <duration>` | Maximum wait time for first log entry |
| `--capture <duration>` | Capture duration after first log arrives |
| `--count <n>` | Number of entries to capture |

Duration format: `5s`, `30s`, `2m`, `1h` (number without suffix = seconds)

**Exit codes:** `0` = capture complete or user interrupt, `1` = timeout exceeded or stream error.

## Output Formats

### Color (default)

ANSI-colored output with full details:

```
21:46:22.908 [DEFAULT] Finder[21162] (com.apple.finder:) Starting sync
21:46:22.910 [ERROR] Finder[21162] (com.apple.finder:) Connection failed
```

### Compact

Minimal output with timestamp, level, and message only:

```
21:46:22.908 [DEFAULT] Starting sync
21:46:22.910 [ERROR] Connection failed
```

### Plain

Same as color but without ANSI codes (for file output).

### JSON

Newline-delimited JSON for piping to other tools:

```bash
slog stream --process MyApp --format json | jq '.message'
```

### TOON

Token-Optimized Object Notation for LLM consumption. Uses fewer tokens than JSON while preserving the same data. Ideal for AI agent workflows.

## Examples

### Basic Streaming

```bash
# Stream all Finder logs
slog stream --process Finder

# Stream network-related logs
slog stream --subsystem com.apple.network

# Stream errors and faults only
slog stream --level error

# Search for specific messages
slog stream --grep "connection.*failed"

# Exclude noisy messages
slog stream --process MyApp --exclude-grep "heartbeat|keepalive"

# Collapse repeated messages
slog stream --process MyApp --dedup
```

### Historical Logs

```bash
# Last 5 minutes
slog show --last 5m

# Last hour, errors only
slog show --last 1h --process Finder --level error

# Since last boot
slog show --last boot --subsystem com.apple.network

# Specific time range
slog show --start "2024-01-15 10:00:00" --end "2024-01-15 11:00:00"

# From a log archive file
slog show /path/to/file.logarchive

# JSON output for analysis
slog show --last 5m --format json | jq '.message'
```

### iOS Simulator

```bash
# Auto-detect booted simulator
slog stream --simulator --process MyApp

# Specific simulator by UDID
slog stream --simulator-udid XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX --process MyApp

# Find available simulators
slog list simulators --booted
```

### Automation & Scripting

```bash
# Capture exactly 50 log entries
slog stream --process MyApp --count 50

# Wait up to 1 minute for app to start logging, then capture for 30 seconds
slog stream --process MyApp --timeout 1m --capture 30s

# Fail fast if no logs within 5 seconds
slog stream --process MyApp --timeout 5s || echo "App not logging"

# JSON output for parsing
slog stream --process MyApp --count 10 --format json > logs.json
```

### Profiles

```bash
# Create a reusable profile
slog profile create myapp --process MyApp --subsystem com.myapp --level debug --format compact

# Use it
slog stream --profile myapp

# Override specific options
slog stream --profile myapp --level error --format json

# Manage profiles
slog profile list
slog profile show myapp
slog profile delete myapp
```

## Log Levels

From most to least verbose:

| Level | Value | Description |
|-------|-------|-------------|
| `debug` | 0 | Debugging information |
| `info` | 1 | Informational messages |
| `default` | 2 | Default level |
| `error` | 16 | Error conditions |
| `fault` | 17 | Critical failures |

When filtering by `--subsystem`, debug logs are automatically included. Override with explicit `--level`.

## MCP Server Integration

slog can run as an MCP server, making log querying available to AI agents for automated workflows.

### Setup

1. Install slog via Homebrew
2. Run `slog mcp --setup` for configuration instructions
3. If your AI agent is not listed, configure manually:

```json
{
  "mcpServers": {
    "slog": {
      "command": "slog",
      "args": ["mcp"]
    }
  }
}
```

4. Restart your MCP client

### Available Tools

All log commands are exposed as MCP tools with the `slog_` prefix:
- `slog_show` — Query historical logs with filters and time ranges
- `slog_stream` — Stream live logs with bounded capture (max 1000 entries)
- `slog_list_processes` — List running processes with optional name filter
- `slog_list_simulators` — List iOS Simulators
- `slog_doctor` — Check system requirements

MCP tools return JSON format. For token-optimized output, use the CLI with `--format toon`.

### AI Agent Skill

A comprehensive skill guide is available in `skills/slog/SKILL.md` that teaches AI agents how to use slog effectively. The skill includes detailed command examples, filtering strategies, and best practices optimized for AI agent usage.

## Building

```bash
swift build                     # Debug build
swift build -c release          # Release build
swift run slog stream --process Finder  # Run directly
swift test                      # Run tests
```

## License

MIT License — see [LICENSE](LICENSE) for details.
