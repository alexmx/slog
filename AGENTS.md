# slog

## What is slog?

slog is a Swift CLI tool and MCP server for intercepting and filtering macOS/iOS logs. It wraps Apple's `log` CLI to provide enhanced filtering, formatting, iOS Simulator support, and time-bounded capture for automation workflows.

## Project Structure

```
slog/
├── Package.swift                       # SPM manifest (macOS 26+, Swift 6.2)
├── Sources/slog/
│   ├── Commands/                       # One file per CLI command (ArgumentParser)
│   │   ├── RootCommand.swift           # @main entry point with 6 subcommands
│   │   ├── StreamCommand.swift         # Live log streaming with filters
│   │   ├── ShowCommand.swift           # Historical log queries
│   │   ├── ProfileCommand.swift        # Profile management (create/list/show/delete)
│   │   ├── ListCommand.swift           # List processes/simulators
│   │   ├── DoctorCommand.swift         # System requirements checker
│   │   └── MCPCommand.swift            # MCP server for AI tool integration
│   ├── Core/                           # Log handling and shared services
│   │   ├── LogEntry.swift              # LogEntry struct, LogLevel enum
│   │   ├── LogParser.swift             # NDJSON and legacy format parser
│   │   ├── LogStreamer.swift           # Stream process management, PredicateBuilder
│   │   ├── LogReader.swift             # Historical log reading via `log show`
│   │   ├── DurationParser.swift        # Duration string parsing (e.g., "5s", "2m")
│   │   ├── SystemQuery.swift           # Process/simulator listing, UDID resolution
│   │   ├── DoctorCheck.swift           # System requirement checks
│   │   └── Version.swift               # Version constant (overridden by CI)
│   ├── Config/                         # Configuration and profiles
│   │   ├── XDGDirectories.swift        # XDG-compliant path resolution
│   │   ├── Profile.swift               # Profile data model (Codable)
│   │   └── ProfileManager.swift        # Profile CRUD operations
│   ├── Filters/                        # Filtering system
│   │   ├── FilterChain.swift           # Thread-safe filter chain with DSL
│   │   ├── FilterSetup.swift           # Predicate + filter chain + auto-debug builder
│   │   └── Predicates.swift            # 10+ composable predicate types
│   ├── MCP/
│   │   └── SlogTools.swift             # 5 MCP tool definitions reusing core logic
│   └── Output/                         # Formatters
│       ├── Formatter.swift             # Protocol, registry, OutputFormat enum
│       ├── FormattedEntry.swift        # Shared Encodable model for JSON/TOON
│       ├── PlainFormatter.swift        # Plain text output
│       ├── ColorFormatter.swift        # ANSI-colored output
│       ├── JSONFormatter.swift         # JSON output
│       ├── ToonFormatter.swift         # TOON output (token-optimized)
│       └── DedupWriter.swift           # Consecutive message deduplication
├── Sources/TestEmitter/
│   └── main.swift                      # Test log emitter for end-to-end testing
└── Tests/slogTests/                    # Apple Testing framework tests
```

## Build & Run

```bash
swift build                     # Debug build
swift build -c release          # Release build
swift run slog [args]           # Run the tool
swift test                      # Run all tests
```

**AI agents:** Always use the **haiku model with a Bash subagent** when running `swift build`, `swift test`, `git commit`, or `git push` to minimize cost and latency.

**Requirements:** macOS 26+, Swift 6.2, Xcode toolchain.

**Dependencies:**
- `swift-argument-parser` — CLI argument parsing
- `swift-subprocess` — Modern async process execution
- `Rainbow` — ANSI color support for terminal output
- `ToonFormat` — TOON (Token-Oriented Object Notation) encoding
- `SwiftMCP` (`swift-cli-mcp`) — MCP server framework

## Version Management & Releases

**Version Source:** `.slog-version` file in repository root

- Single source of truth for version number (e.g., `0.1.0` or `dev`)
- `Sources/slog/Version.swift` defines `slogVersion` constant (defaults to "dev" for local builds)
- GitHub Actions reads `.slog-version`, generates `Version.swift` with actual version, then builds release binary
- CLI exposes version via `slog --version`

**Release Process:**

1. Update `.slog-version` with new version (e.g., `0.1.0`)
2. Commit and push to main
3. Manually trigger "Release" workflow from GitHub Actions
4. Workflow creates git tag, builds universal binary, publishes GitHub release
5. Automatically updates Homebrew formula in `homebrew-tools` repository with new SHA256

**Homebrew Distribution:**

Users install via:
```bash
brew tap alexmx/tools
brew install slog
```

Formula location: `alexmx/homebrew-tools/Formula/slog.rb`

## Commands

Six subcommands. `stream` is the default (can be omitted).

### Streaming & Querying
- **stream** — Stream live logs. Filters: `--process`, `--subsystem`, `--category`, `--level`, `--grep`, `--exclude-grep`. Output: `--format`, `--time`, `--info`, `--debug`, `--source`, `--dedup`. Bounded capture: `--timeout`, `--capture`, `--count`.
- **show** — Query historical logs. Requires `--last`, `--start`, or archive path. Same filters and output options as stream.

### Configuration
- **profile** — CRUD for saved filter/format profiles. `create`, `list`, `show`, `delete`. Use `--profile <name>` on stream/show.

### Discovery
- **list** — `list processes [--filter]`, `list simulators [--booted] [--all]`.

### System
- **doctor** — Check system requirements (log CLI, stream/archive access, simctl, profiles dir).
- **mcp** — Start MCP server. `--setup` for integration instructions.

## Testing

Uses Apple's Testing framework (`@Suite`, `@Test`, `#expect()`, `#require()`).

```bash
swift test                    # Run all tests
swift test --filter <name>    # Run specific test
```

**Test emitter** — separate executable for end-to-end testing:
```bash
swift run slog-test-emitter              # Emit all test logs once
swift run slog-test-emitter --repeat 5   # Repeat 5 times
swift run slog-test-emitter --continuous  # Emit every second until Ctrl+C
```

## Adding a New Command

1. Create `Sources/slog/Commands/NewCommand.swift` implementing `AsyncParsableCommand`
2. Register it as a subcommand in `RootCommand.swift`
3. Put shared business logic in `Core/` (e.g., a new service struct/enum)
4. Add the corresponding MCP tool in `MCP/SlogTools.swift`
5. Add tests in `Tests/slogTests/`

## Swift Style

- Swift 6.2 with modern concurrency (async/await, Sendable types)
- Protocol-based extensibility (LogFormatter, LogPredicate)
- Builder pattern for predicates and filter chains
- Shared services called by both CLI commands and MCP tools (thin wrappers)

## Formatting

```bash
swiftformat .
```

## Git Commits

**Never add `Co-Authored-By` attribution to commits.** Write commit messages without any co-author trailers.
