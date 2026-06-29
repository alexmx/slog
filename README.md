# slog

Tame the macOS log firehose from your terminal.

<p align="center">
  <img width="1280" height="914" alt="slog color output showing filtered logs with mixed levels" src="https://github.com/user-attachments/assets/85da8a0c-a5ef-4c7a-912a-0ba64ba0d080" />
</p>

A macOS CLI tool and MCP server for streaming, filtering, and querying system logs. slog wraps Apple's unified logging system to provide powerful filtering by process, subsystem, level, and regex—with multiple output formats, saved profiles, iOS Simulator support, and time-bounded capture for automation workflows. Use it from the command line or through an MCP server optimized for AI agents.

## Features

- **Stream & query logs** from macOS or iOS Simulator in real-time or from history
- **Signpost interval timing** via `--signpost` — pair `os_signpost` begin/end events into per-name durations (count/p50/max/total) without Instruments
- **Powerful filtering** by process, subsystem, category, log level, and regex patterns
- **Multiple output formats**: plain, compact, colored, JSON, and TOON (token-optimized for LLMs)
- **Saved profiles** for reusable filter/format combinations
- **Time-bounded capture** with `--timeout`, `--capture`, and `--count` for scripting
- **Auto-detection** of booted iOS Simulators
- **MCP server** for AI agent integration

## Installation

### Homebrew

```bash
brew install alexmx/tools/slog
```

### Mise

```bash
mise use --global github:alexmx/slog
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
| `stream` | Stream live logs (default command) | `--process` `--subsystem` `--level` `--grep` `--format` `--count` `--signpost` | `slog stream --process MyApp --level error` |
| `show` | Query historical logs | `--last` `--start`/`--end` `--process` `--format` `--limit` `--signpost` | `slog show --last 5m --format json` |

**Signpost mode** (`--signpost` on `stream`/`show`): report `os_signpost` interval durations instead of log messages. Pairs begin↔end by (process, signpost name, signpost id) so concurrent same-name intervals stay distinct, and aggregates per name. Live `stream --signpost` needs no persistence; `show --signpost` reads the persisted store. Works with `--format json`/`toon`.

```sh
$ slog stream --signpost --subsystem com.myapp --category perf --capture 20s
interval         count  p50     max     total   last args
parse.postImage  3      42.8ms  45.1ms  128ms   len 208123
attr.chunk       7      1.1ms   7.0ms   9.8ms   start 0
```

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
| `--process <name>` | Filter by process name. Comma-separated for multiple (OR-matched), e.g. `Finder,Dock` |
| `--pid <id>` | Filter by process ID |
| `--simulator` | Stream from iOS Simulator instead of macOS |
| `--simulator-udid <udid>` | Specific simulator UDID (auto-detects if omitted) |

### Filter Options

| Option | Description |
|--------|-------------|
| `--subsystem <name>` | Filter by subsystem (e.g., `com.apple.network`). Comma-separated for multiple (OR-matched) |
| `--category <name>` | Filter by category. Comma-separated for multiple (OR-matched), e.g. `http,dns` |
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

# Stream multiple processes or subsystems (comma-separated, OR-matched)
slog stream --process Finder,Dock
slog stream --subsystem com.apple.network,com.apple.CFNetwork

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

### Signpost Timing

```bash
# Live: capture interval durations while exercising the app (no persistence needed)
slog stream --signpost --subsystem com.myapp --category perf --capture 20s

# Historical: read persisted signposts from the last 5 minutes
slog show --last 5m --signpost --subsystem com.myapp --category perf

# JSON for analysis (includes per-occurrence start/duration/args)
slog show --last 5m --signpost --subsystem com.myapp --format json

# If `show --signpost` finds nothing, enable persistence for the subsystem first
sudo log config --subsystem com.myapp --mode persist:debug
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

Debug and info are excluded by default. Filtering by `--subsystem` auto-includes both (auto-debug); otherwise request them explicitly with `--level debug` / `--level info` (or `--debug` / `--info`). A higher floor like `--level error` shows only that level and above. Note that `debug` is live-only — visible in `stream` but not persisted for `show` unless enabled via `sudo log config --subsystem <name> --mode persist:debug`.

## MCP Server Integration

slog can run as an MCP server, making log querying available to AI agents for automated workflows.

### Setup

1. Run `slog mcp --setup` for configuration instructions
2. If your AI agent is not listed, configure manually:

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

3. Restart your MCP client

Alternatively, install the [slog skill](skills/use-slog/SKILL.md) with [Skillman](https://github.com/alexmx/skillman) if you don't need the MCP server and prefer to use the CLI for your AI agent:

```bash
skillman install github.com/alexmx/slog
```

### Available Tools

All log commands are exposed as MCP tools with the `slog_` prefix:
- `slog_show` — Query historical logs with filters and time ranges
- `slog_stream` — Stream live logs with bounded capture (max 1000 entries, default 30s timeout)
- `slog_signpost` — Report `os_signpost` interval durations (begin/end pairs) for a subsystem/category; persisted query or live capture (`live: true`)
- `slog_list_processes` — List running processes with optional name filter
- `slog_list_simulators` — List iOS Simulators
- `slog_doctor` — Check system requirements

MCP tools return JSON. For token-optimized CLI output, use `--format toon`.

`slog_show` and `slog_stream` accept `process`, `subsystem`, and `category` as JSON arrays (e.g. `"process": ["Finder", "Dock"]`); multiple values are OR-matched.

Responses are designed to keep agent contexts small: large result sets come back as a summary plus head/tail samples, with the full payload written as NDJSON to a spill file the agent can read selectively. `slog_show` also supports aggregate-only queries, replaying a previous spill instead of re-scanning, and tailing via a `next_since` cursor.

For the full contract — every arg, every response field, agent workflow patterns — see [`skills/use-slog/SKILL.md`](skills/use-slog/SKILL.md) or the tool descriptions surfaced by the MCP server itself.

## License

MIT License — see [LICENSE](LICENSE) for details.
