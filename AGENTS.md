# slog

Swift CLI + MCP server wrapping Apple's `log` for filtered, formatted, time-bounded macOS/iOS log capture.

## Project Structure

```
slog/
├── Package.swift                       # SPM manifest (macOS 15+, Swift 6.2)
├── Sources/slog/
│   ├── Commands/                       # One file per CLI command (ArgumentParser)
│   │   ├── RootCommand.swift           # @main, 6 subcommands
│   │   ├── StreamCommand.swift         # Live streaming
│   │   ├── ShowCommand.swift           # Historical queries
│   │   ├── ProfileCommand.swift        # Profile CRUD
│   │   ├── ListCommand.swift           # Processes / simulators
│   │   ├── DoctorCommand.swift         # System checks
│   │   └── MCPCommand.swift            # MCP server entry
│   ├── Core/                           # Log handling + shared services
│   │   ├── LogEntry.swift              # LogEntry, LogLevel
│   │   ├── LogParser.swift             # NDJSON + legacy parser
│   │   ├── LogStreamer.swift           # `log stream` driver + PredicateBuilder
│   │   ├── LogReader.swift             # `log show` driver
│   │   ├── SignpostAggregator.swift    # Pairs os_signpost begin/end → intervals
│   │   ├── DurationParser.swift        # "5s", "2m" → Duration
│   │   ├── SystemQuery.swift           # Processes / simulators / UDID
│   │   ├── DoctorCheck.swift           # System requirement checks
│   │   └── Version.swift               # Version constant (CI-overridden)
│   ├── Config/
│   │   ├── XDGDirectories.swift        # XDG path resolution
│   │   ├── Profile.swift               # Profile model
│   │   └── ProfileManager.swift        # Profile CRUD
│   ├── Filters/
│   │   ├── FilterChain.swift           # Thread-safe filter chain
│   │   ├── FilterSetup.swift           # Predicate + chain + auto-debug builder
│   │   └── Predicates.swift            # Composable predicate types
│   ├── MCP/
│   │   ├── SlogTools.swift             # 6 MCP tool definitions
│   │   └── SlogResultEnvelope.swift    # ResultSummary, NDJSONSpill, envelope builders
│   └── Output/                         # Formatters
│       ├── Formatter.swift             # Protocol, registry, OutputFormat
│       ├── FormattedEntry.swift        # Shared Encodable model (JSON/TOON)
│       ├── FormattedSignpost.swift     # Shared Encodable model for signpost output
│       ├── SignpostFormatter.swift     # Signpost table / JSON / TOON renderer
│       ├── PlainFormatter.swift
│       ├── ColorFormatter.swift
│       ├── JSONFormatter.swift
│       ├── ToonFormatter.swift         # Token-optimized
│       └── DedupWriter.swift           # Collapses consecutive identical messages
├── Sources/TestEmitter/main.swift      # Test log emitter for e2e
└── Tests/slogTests/                    # Apple Testing framework
```

## Build, Test, Run

```bash
swift build [-c release]
swift test [--filter <name>]
swift run slog [args]
swiftformat .
```

**Requirements:** macOS 15+, Swift 6.2, Xcode toolchain.

**Dependencies:** `swift-argument-parser`, `swift-subprocess`, `Rainbow` (ANSI), `ToonFormat`, `SwiftMCP` (`swift-cli-mcp`).

**Test emitter** (separate executable for e2e):
```bash
swift run slog-test-emitter [--repeat N | --continuous] [--signpost]
```
`--signpost` emits `os_signpost` intervals (concurrent same-name, in-flight, event) instead of os_log messages.

## Commands

Six subcommands; `stream` is the default. See `slog --help` or `skills/slog/SKILL.md` for flags.

- **stream** — Live logs, bounded by `--timeout` / `--capture` / `--count`.
- **show** — Historical logs from `--last` / `--start`/`--end` / archive path. Caps display with `--limit` (not `--count`).
- **stream/show `--signpost`** — Report `os_signpost` interval durations instead of log messages. Pairs begin↔end by (process, signpost name, signpost id), aggregates per name (count/p50/max/total), and prints a table (or `--format json`/`toon`). In-flight begins show null duration. Live `stream --signpost` needs no persistence; `show --signpost` reads the persisted store (custom subsystems may need `log config --mode persist:debug`).
- **profile** — `create` / `list` / `show` / `delete` saved filter combos. Apply via `--profile <name>` on stream/show.
- **list** — `list processes [--filter]`, `list simulators [--booted] [--all]`.
- **doctor** — Verify log CLI / stream / archive access, simctl, profiles dir.
- **mcp** — Start MCP server. `--setup` prints integration instructions.

## MCP Response Envelope

Shared by `slog_show`, `slog_stream`, `slog_list_processes` (in `MCP/SlogResultEnvelope.swift`):

- ≤50 items → inline. >50 items → `summary` (where applicable) + `head`/`tail` (10 each) + NDJSON spill at `output_file` (default `$XDG_CACHE_HOME/slog/runs/`).
- `full: true` → inline everything.
- `slog_show` extras: `summary_only: true` (just the aggregate); `source_file: "<path>"` (re-query a previous spill, skip the OS scan); `next_since` in every response (latest matched timestamp + 1µs) for tailing — pass back as next `start`; `scan_capped: true` when the 100k-event ceiling is hit. `limit` caps **retained** entries; summary always covers the full matched population.
- `slog_stream.count` is optional (1–1000); omit to capture until `timeout`, capped at 1000. When `stopped_by == "error"` the response carries `error_message`; if `captured == 0` it also sets `try_doctor: true`.
- `slog_signpost` does **not** use the shared envelope. It returns aggregated intervals: `{ count, in_flight, orphan_ends, elapsed_ms, mode, intervals, hint? }`, where `intervals` is grouped by name with `min_ms`/`p50_ms`/`max_ms`/`total_ms` (nil stats omitted). `full: true` adds per-occurrence detail. `mode: "stream"` (live capture, set `live: true`) vs `"show"` (persisted query via `last`/`start`/`archive_path`).
- Error payloads are `{ "error": ... }`; system-level failures (missing CLI, permission denied, simctl issues) add `"try_doctor": true` to steer the caller toward `slog_doctor`.

`ResultEnvelopeBuilder` is `LogEntry`-specific (computes `ResultSummary`); `ListEnvelopeBuilder<T: Encodable>` handles list-style tools without a summary.

## Adding a New Command

1. `Sources/slog/Commands/NewCommand.swift` implementing `AsyncParsableCommand`.
2. Register as a subcommand in `RootCommand.swift`.
3. Shared logic in `Core/` (service struct/enum).
4. Add the MCP tool in `MCP/SlogTools.swift`.
5. Tests in `Tests/slogTests/` (Apple Testing: `@Suite`, `@Test`, `#expect`, `#require`).

## Conventions

- Swift 6.2; async/await, Sendable types.
- Protocol-based extensibility (`LogFormatter`, `LogPredicate`).
- Builder pattern for predicates and filter chains.
- CLI commands and MCP tools share the same Core services (thin wrappers).

## Versioning & Release

- `.slog-version` at repo root is the source of truth. `Sources/slog/Version.swift` defaults to `"dev"`; CI generates the real value before building.
- Release: bump `.slog-version` → push → trigger "Release" workflow in GitHub Actions → workflow tags, builds universal binary, publishes release, updates `alexmx/homebrew-tools/Formula/slog.rb` SHA256.
- Homebrew install: `brew install alexmx/tools/slog`.

## Git

- **Never** add `Co-Authored-By` trailers.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, etc.) with scope where it helps.
