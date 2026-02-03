# slog

A fast, modern Swift CLI for streaming and filtering macOS and iOS Simulator logs.

slog wraps Apple's `log` CLI to provide enhanced filtering, multiple output formats, and time-bounded capture for automation workflows.

## Features

- **Stream logs** from macOS or iOS Simulator in real-time
- **Powerful filtering** by process, subsystem, category, log level, and regex patterns
- **Multiple output formats**: plain, compact, colored, and JSON
- **Time-bounded capture** with `--timeout`, `--capture`, and `--count` for scripting
- **Auto-detection** of booted iOS Simulators
- **Modern Swift** built with async/await and Swift Concurrency

## Installation

### From Source

Requires Swift 6.2+ and macOS 15+.

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

# Capture 10 log entries and exit
slog stream --process MyApp --count 10

# Wait up to 30s for logs, then capture for 10s
slog stream --process MyApp --timeout 30s --capture 10s
```

## Usage

### Stream Command

The `stream` command is the default and can be omitted.

```bash
slog stream [options]
slog [options]  # equivalent
```

#### Target Options

| Option | Description |
|--------|-------------|
| `--process <name>` | Filter by process name |
| `--pid <id>` | Filter by process ID |
| `--simulator` | Stream from iOS Simulator instead of macOS |
| `--simulator-udid <udid>` | Specific simulator UDID (auto-detects if omitted) |

#### Filter Options

| Option | Description |
|--------|-------------|
| `--subsystem <name>` | Filter by subsystem (e.g., `com.apple.network`) |
| `--category <name>` | Filter by category |
| `--level <level>` | Minimum log level: `debug`, `info`, `default`, `error`, `fault` |
| `--grep <pattern>` | Filter messages by regex pattern |

#### Output Options

| Option | Description |
|--------|-------------|
| `--format <fmt>` | Output format: `plain`, `compact`, `color` (default), `json` |
| `--info` | Include info-level messages |
| `--debug` | Include debug-level messages |

#### Timing Options

For scripting and automation workflows:

| Option | Description |
|--------|-------------|
| `--timeout <duration>` | Maximum wait time for first log entry |
| `--capture <duration>` | Capture duration after first log arrives |
| `--count <n>` | Number of entries to capture |

Duration format: `5s`, `30s`, `2m`, `1h` (number without suffix = seconds)

**Exit codes:**
- `0` - Capture complete or user interrupt
- `1` - Timeout exceeded (no logs received) or stream error

### List Command

```bash
# List running processes
slog list processes
slog list processes --filter myapp

# List iOS Simulators
slog list simulators
slog list simulators --booted
slog list simulators --all  # include unavailable
```

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

# Combine: wait 30s, capture 10s or 100 entries (whichever first)
slog stream --process MyApp --timeout 30s --capture 10s --count 100

# JSON output for parsing
slog stream --process MyApp --count 10 --format json > logs.json
```

### Filtering by Subsystem

When filtering by `--subsystem`, debug logs are automatically included (most unified logging uses debug level):

```bash
# Automatically includes debug level
slog stream --subsystem com.myapp.networking

# Override with explicit level
slog stream --subsystem com.myapp.networking --level error
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

## Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run directly
swift run slog stream --process Finder

# Run tests
swift test
```

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
