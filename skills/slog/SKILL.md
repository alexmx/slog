---
name: slog
description: Use the slog CLI to stream, query, and filter macOS/iOS logs. Use when the user asks to debug log output, filter logs by process or subsystem, stream from simulators, query historical logs, or automate log capture.
argument-hint: [command]
---

# slog — macOS/iOS Log Streaming CLI

Use `slog` to stream, query, and filter macOS and iOS Simulator logs. It wraps Apple's `log` CLI to provide enhanced filtering, multiple output formats, and time-bounded capture for automation.

Help the user construct the right slog command for their needs.

## Quick Workflow

```bash
# 1. Check system requirements
slog doctor

# 2. Find the process you want to monitor
slog list processes --filter MyApp

# 3. Stream live logs from it
slog stream --process MyApp

# 4. Narrow down with filters
slog stream --process MyApp --subsystem com.myapp.network --level error

# 5. Query recent historical logs
slog show --last 5m --process MyApp --format json

# 6. Save a reusable profile
slog profile create myapp --process MyApp --subsystem com.myapp --format compact
slog stream --profile myapp
```

## Commands Reference

### `slog stream` — Stream live logs (default command)

```bash
slog stream [options]
slog [options]  # equivalent — stream is the default command
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

```bash
$ slog stream --process Finder --format color
21:46:22.908 [DEFAULT] Finder[21162] (com.apple.finder:) Starting sync
21:46:22.910 [ERROR] Finder[21162] (com.apple.finder:) Connection failed
21:46:22.912 [INFO] Finder[21162] (com.apple.finder:) Retry scheduled
```

```bash
$ slog stream --process MyApp --format json --count 2
{"category":"general","level":"Info","message":"App launched","pid":1234,"process":"MyApp","subsystem":"com.myapp","timestamp":"2026-01-15T10:30:00Z"}
{"category":"general","level":"Error","message":"Network timeout","pid":1234,"process":"MyApp","subsystem":"com.myapp","timestamp":"2026-01-15T10:30:01Z"}
```

### `slog show` — Query historical logs

```bash
slog show [options] [archive-path]
```

**Time range (at least one required unless archive-path given):**
- `--last <duration|boot>` — e.g. `5m`, `1h`, `boot`
- `--start <date>` — e.g. `"2024-01-15 10:30:00"`
- `--end <date>` — e.g. `"2024-01-15 11:00:00"`

`--last` and `--start`/`--end` are mutually exclusive.

**Filters:** same as stream (`--process`, `--pid`, `--subsystem`, `--category`, `--level`, `--grep`, `--exclude-grep`).

**Output:** same as stream (`--format`, `--time`, `--info`, `--debug`, `--source`, `--dedup`, `--count`).

```bash
$ slog show --last 5m --process Finder --level error
21:46:22.910 [ERROR] Finder[21162] (com.apple.finder:) Connection failed
```

```bash
$ slog show /path/to/file.logarchive --format toon
```

### `slog profile` — Manage saved filter profiles

Profiles are stored as JSON in `$XDG_CONFIG_HOME/slog/profiles/` (defaults to `~/.config/slog/profiles/`).

```bash
slog profile create <name> [options]   # Create from CLI flags (--force to overwrite)
slog profile list                      # List profiles
slog profile show <name>               # Show profile contents
slog profile delete <name>             # Delete a profile
```

Use with `--profile <name>` on `stream` or `show`. CLI args override profile values. Use `--no-info`, `--no-debug`, `--no-source` to explicitly disable profile flags.

```bash
$ slog profile create myapp --process MyApp --subsystem com.myapp --level debug --format compact
Created profile 'myapp'

$ slog stream --profile myapp
$ slog stream --profile myapp --level error --format json
```

### `slog list` — List processes and simulators

```bash
slog list processes [--filter <name>]     # List running processes
slog list simulators [--booted] [--all]   # List iOS Simulators
```

```bash
$ slog list processes --filter finder
Finder (21162)

$ slog list simulators --booted
iPhone 16e (Booted)  ABC-123-DEF  iOS 18.4
```

### `slog doctor` — Check system requirements

```bash
$ slog doctor
log CLI:          ok
Stream access:    ok
Archive access:   ok
Simulator support: ok
Profiles dir:     ok (/Users/alex/.config/slog/profiles)
```

### `slog mcp` — Start MCP server

```bash
slog mcp            # Start MCP server (stdio transport)
slog mcp --setup    # Print integration instructions
```

Exposes 5 tools: `slog_show`, `slog_stream`, `slog_list_processes`, `slog_list_simulators`, `slog_doctor`.

## Filtering Strategies

When debugging log output, use this efficient approach:

1. **Start broad, then narrow**: First stream by process, then add subsystem/level filters
   ```bash
   # See all logs from your app
   slog stream --process MyApp
   # Then narrow to network errors
   slog stream --process MyApp --subsystem com.myapp.network --level error
   ```

2. **Use grep for message-level filtering**: Combine server-side predicates with client-side regex
   ```bash
   # Find timeout-related errors
   slog stream --process MyApp --level error --grep "timeout|connection"
   # Exclude noisy heartbeat logs
   slog stream --process MyApp --exclude-grep "heartbeat|keepalive"
   ```

3. **Use profiles for repeated queries**: Save complex filter combinations
   ```bash
   slog profile create network-debug --process MyApp --subsystem com.myapp.network --level debug --format compact
   slog stream --profile network-debug
   ```

4. **Use show for post-mortem analysis**: Query historical logs after an issue
   ```bash
   # What happened in the last 5 minutes?
   slog show --last 5m --process MyApp --level error
   # Check logs around a specific time
   slog show --start "2026-01-15 10:30:00" --end "2026-01-15 10:35:00" --process MyApp
   ```

5. **Use bounded capture for automation**: Integrate slog into scripts and CI
   ```bash
   # Capture 10 errors or timeout after 30s
   slog stream --process MyApp --level error --count 10 --timeout 30s --format json
   ```

## Output Formats

All commands support structured output formats via `--format`:
- `color` — ANSI-colored output with full details (default)
- `plain` — Same as color without ANSI codes (for file output/piping)
- `compact` — Minimal: timestamp, level, message only
- `json` — Newline-delimited JSON for programmatic use
- `toon` — Token-Optimized Object Notation for LLM consumption (recommended for AI agents, uses fewer tokens than JSON)

**Always use `--format toon` for AI agent workflows.** It provides the same data as JSON with significantly fewer tokens.

## Key Behaviors

- **Auto-debug**: When filtering by `--subsystem`, debug+info logs are automatically included. Override with explicit `--level`, `--info`, or `--debug`.
- **Log levels** (most to least verbose): `debug` (0), `info` (1), `default` (2), `error` (16), `fault` (17).
- **Exit codes**: 0 = capture complete or user interrupt; 1 = timeout or stream error.
- **Dedup**: Use `--dedup` to collapse consecutive identical messages into "message (xN)".
- **Relative timestamps**: Use `--time relative` to see time deltas between log entries instead of absolute timestamps.

## Tips

- Prefer `--format toon` for AI agent workflows to reduce token usage.
- Use `slog show --last boot` to see all logs since the last system boot.
- Combine `--grep` and `--exclude-grep` for precise message filtering.
- Use `--count` with `--format json` to capture structured log data for analysis.
- Profiles persist filter settings — use `--profile` to avoid retyping complex flag combinations.
- `--source` adds file/function/line info when available (requires the logging framework to emit it).
- When piping to `jq`, use `--format json`: `slog stream --process MyApp --format json | jq '.message'`.
