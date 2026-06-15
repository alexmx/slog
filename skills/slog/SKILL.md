---
name: slog
description: Use the slog CLI to stream, query, and filter macOS/iOS logs. Use when the user asks to debug log output, filter logs by process or subsystem, stream from simulators, query historical logs, or automate log capture.
argument-hint: [command]
---

# slog — macOS/iOS Log Streaming CLI

`slog` wraps Apple's `log` CLI with enhanced filtering, multiple output formats, and bounded capture for automation.

Help the user build the right invocation.

## Quick Workflow

```bash
slog doctor                                    # verify system
slog list processes --filter MyApp             # find process names
slog stream --process MyApp                    # live stream
slog show --last 5m --process MyApp --level error --format json
slog profile create myapp --process MyApp --subsystem com.myapp --format compact
slog stream --profile myapp                    # reuse
```

## Commands

### `slog stream` — live logs (default command, can be omitted)

```bash
slog stream [options]
```

**Target:** `--process <name>` · `--pid <id>` · `--simulator` · `--simulator-udid <udid>` (auto-detects if one is booted)

**Filters:** `--subsystem <name>` · `--category <name>` · `--level <debug|info|default|error|fault>` · `--grep <regex>` · `--exclude-grep <regex>`

`--process`, `--subsystem`, `--category` accept comma-separated multi-values (OR-matched), e.g. `--process Finder,Dock`.

**Output:** `--format <plain|compact|color|json|toon>` · `--time <absolute|relative>` · `--info`/`--no-info` · `--debug`/`--no-debug` · `--source`/`--no-source` · `--dedup`/`--no-dedup`

**Bounded capture (for automation):** `--timeout <duration>` (max wait for first log, exits 1 on miss) · `--capture <duration>` (after first log) · `--count <n>`. Duration: `5s`, `30s`, `2m`, `1h`.

```bash
$ slog stream --process MyApp --format json --count 2
{"category":"general","level":"Info","message":"App launched","pid":1234,"process":"MyApp","subsystem":"com.myapp","timestamp":"2026-01-15T10:30:00Z"}
{"category":"general","level":"Error","message":"Network timeout","pid":1234,"process":"MyApp","subsystem":"com.myapp","timestamp":"2026-01-15T10:30:01Z"}
```

### `slog show` — historical logs

```bash
slog show [options] [archive-path]
```

**Time range (one required unless `archive-path` given):** `--last <5m|1h|boot>` · `--start <date>` · `--end <date>`. `--last` and `--start`/`--end` are mutually exclusive.

**Filters:** same as stream.

**Output:** same as stream plus `--limit <n>` to cap displayed entries (note: show uses `--limit`, stream uses `--count`).

```bash
$ slog show --last 5m --process Finder --level error
21:46:22.910 [ERROR] Finder[21162] (com.apple.finder:) Connection failed
```

### `slog profile` — saved filter profiles

Stored in `$XDG_CONFIG_HOME/slog/profiles/` (defaults to `~/.config/slog/profiles/`).

```bash
slog profile create <name> [options]    # --force to overwrite
slog profile list | show <name> | delete <name>
```

Apply with `--profile <name>` on `stream`/`show`. CLI args override profile values. Use `--no-info`/`--no-debug`/`--no-source` to disable profile flags.

### `slog list` — processes / simulators

```bash
slog list processes [--filter <name>]
slog list simulators [--booted] [--all]
```

### `slog doctor` — check system requirements

```bash
$ slog doctor
  [OK] log CLI · Log stream access · Log archive access · Simulator support · Profiles directory
All checks passed.
```

### `slog mcp` — start MCP server (stdio)

```bash
slog mcp [--setup]    # --setup prints integration instructions
```

Exposes 5 tools: `slog_show`, `slog_stream`, `slog_list_processes`, `slog_list_simulators`, `slog_doctor`. `process`/`subsystem`/`category` accept JSON arrays (OR-matched).

**Response envelope** (shared by `slog_show`/`slog_stream`/`slog_list_processes`):
- ≤50 items → fully inline (`entries`/`processes`).
- &gt;50 items → `summary` (where applicable) + `head`/`tail` (10 each) + `output_file` (full payload as NDJSON). **Read with `Read offset/limit` or `jq`; don't slurp.**
- `output_file: "<path>"` overrides spill destination (default `$XDG_CACHE_HOME/slog/runs/`).
- `full: true` inlines everything.
- `truncated: true` flags which path was taken.

**`slog_show` extras:**
- `summary_only: true` → just `{ count, elapsed_ms, scan_capped, summary, next_since?, hint? }`. Best for aggregate questions. Mutex with `full`.
- `limit: N` (default 500) caps **retained** entries; summary always covers the full population, scanning up to 100k events. `scan_capped: true` → narrow the window.
- `source_file: "<path>"` re-queries a previous `output_file` instead of the OS log database — same filters, same envelope, milliseconds instead of seconds. Use for iterative drill-down. Mutex with `last`/`start`/`end`/`archive_path` and with `output_file == source_file`.
- `next_since` (always in the response, `null` when 0 matches) = latest matched timestamp + 1µs. **For tailing, pass it back as the next `start` to fetch only what's new** — works in `summary_only` too.
- `hint` appears only when `count == 0`.

**`slog_stream` extras:** `captured`, `requested`, `stopped_by` (`count` | `timeout` | `exhausted` | `error`). `count` is optional (1–1000) — omit it to capture until `timeout`, implicitly capped at 1000.

## Filtering Strategies

1. **Start broad, narrow down.** Process → add subsystem/level/grep.
2. **Combine server + client filters.** Predicate (`--process`, `--subsystem`, `--category`, `--level`) runs server-side; `--grep`/`--exclude-grep` run on the message after retrieval.
3. **OR multiple values.** `--process Finder,Dock`, `--subsystem com.apple.network,com.apple.CFNetwork`.
4. **Save profiles** for repeated combinations.
5. **`show` for post-mortem, `stream` for live + debug events.** Custom subsystems don't persist debug events by default — `show` won't see them.

## Output Formats

- `color` (default) — ANSI-colored, full details
- `plain` — same as color, no ANSI
- `compact` — timestamp + level + message only
- `json` — NDJSON for piping (`| jq '.message'`)
- `toon` — TOON, fewer tokens than JSON

**Use `--format toon` for AI agent workflows.**

## Key Behaviors

- **Auto-debug:** filtering by `--subsystem` auto-includes debug+info. Override with `--level`/`--info`/`--debug`.
- **Levels** (least→most verbose): `debug`, `info`, `default`, `error`, `fault`.
- **Exit codes:** 0 = capture complete or user interrupt · 1 = timeout or stream error.
- **Dedup:** `--dedup` collapses consecutive identical messages into "message (xN)".
- **Relative timestamps:** `--time relative` shows deltas between entries.

## Tips

- `--format toon` for agent workflows.
- `slog show --last boot` for all logs since last boot.
- Bound for analysis: `slog show --limit N --format json` or `slog stream --count N --format json`.
- Profiles avoid retyping complex flag combos.
- `--source` adds file/function/line info when emitted by the logger.
