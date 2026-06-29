---
name: use-slog
description: Stream, query, and filter macOS/iOS unified logs via the slog CLI or MCP tools. Use whenever debugging log output, filtering by process/subsystem/category, streaming from a simulator, querying historical logs, reading os_signpost timings, or troubleshooting why expected logs (os_log/Logger) "aren't showing up" — even if the user doesn't name slog.
argument-hint: [command]
---

# slog — macOS/iOS unified-log streaming (CLI + MCP)

`slog` wraps Apple's `/usr/bin/log` (CLI + MCP server) with filtering, formatting,
and bounded capture. **It only sees what the macOS unified logging system
records** — most "slog can't see my logs" reports are a visibility, level, or
persistence issue below, not a bug. CLI and MCP share one engine, so the
**workflow rules are identical**; only the surface differs. Read these two
sections first.

## What slog can and cannot see

| ✅ Visible (in the unified log) | ❌ Invisible (never enters it) |
|---|---|
| `os_log(...)` — all levels | `print()` / `debugPrint()` → stdout |
| `os.Logger` — `trace/debug/info/notice/warning/error/critical/fault` | `fputs`/`FileHandle.standardError` → stderr |
| `os_signpost` intervals/events | **`NSLog()`** — stderr-only for CLI binaries; unreliable |
| | `swift-log`/CocoaLumberjack on their **default** (stdout) backend |

- **`print`/`NSLog` are unreachable by any flag** — fix at the source (use `os.Logger`). Logs visible in Xcode's console aren't necessarily in the unified log; Xcode also captures raw stdio.
- **`<private>` is redaction, not a bug.** Interpolated values in `os_log`/`Logger` are masked unless marked `privacy: .public` at the call site; the line is still captured. String literals are always shown.

## Workflow rules (CLI and MCP)

These five prevent ~all false "missing logs" conclusions. Each maps to a CLI flag and an MCP arg.

| Rule | CLI | MCP |
|---|---|---|
| **1. Filter by subsystem** — auto-enables debug+info ("auto-debug") | `--subsystem com.app` | `subsystem: ["com.app"]` |
| **2. Or set the level floor** — `debug`/`info` floors also enable emission | `--level debug`/`info` | `level: "debug"`/`"info"` |
| **3. Debug → stream; historical default+ → show** | `slog stream` / `slog show` | `slog_stream` / `slog_show` |
| **4. Signposts need their own mode** | `--signpost` | `slog_signpost` (`live: true`) |
| **5. Multi-value = OR** | `--process Finder,Dock` | `process: ["Finder","Dock"]` |

**Getting debug/info (rules 1–2).** `--level`/`level` is a *minimum severity*, and a `debug`/`info` floor now also *enables emission* of those levels (it used to silently capture nothing — fixed). Equivalent ways to surface debug:

```bash
slog stream --subsystem com.app                # auto-debug: debug+info, no level needed
slog stream --process App --level debug        # explicit floor; works without a subsystem
slog stream --subsystem com.app --level error  # error+fault only — debug/info correctly excluded
```

**Persistence (rule 3).** `debug`/`trace` are **live-only**, not written to disk, so `slog stream` sees them but `slog show --last` doesn't (`info` is persisted; `error`/`fault` always). Reproducing now → `stream` (no setup). Need debug in history → `sudo log config --subsystem com.app --mode persist:debug`.

## Core workflow

```bash
slog doctor                                  # 1. verify system access
slog list processes --filter MyApp           # 2. find the process name (skip if known)
slog stream --subsystem com.myapp            # 3. live + debug (auto-debug)
slog show --last 1h --subsystem com.myapp --level error    # 4. historical errors
slog stream --subsystem com.myapp --grep 'timeout|retry'   # 5. narrow with message regex
```

Broad → narrow: start from `--subsystem` (not process-only), then add `--category`, `--grep`, or a level floor.

## CLI reference

**`slog stream`** — live logs (default command; `slog` alone works).
**`slog show [archive-path]`** — historical logs; needs a time range (`--last 5m|1h|boot`, or `--start`/`--end`).

Shared options:
- **Target:** `--process <name>` · `--pid <id>` · `--simulator` · `--simulator-udid <udid>`
- **Filter:** `--subsystem` · `--category` · `--level <debug|info|default|error|fault>` · `--grep <regex>` · `--exclude-grep <regex>` (process/subsystem/category take comma-separated OR values)
- **Output:** `--format <plain|compact|color|json|toon>` · `--time <absolute|relative>` · `--info`/`--debug`/`--source`/`--dedup` (each with `--no-`)
- **Bound (automation):** `stream` uses `--count <n>` · `--capture <dur>` (after first log) · `--timeout <dur>` (exits 1 if no first log); `show` uses `--limit <n>`. Durations: `5s`, `2m`, `1h`.

**`--signpost`** (on stream/show) — report `os_signpost` interval durations instead of messages (pairs begin↔end by process/name/id; in-flight begins show null). Live `stream --signpost` needs no persistence; `show --signpost` reads the persisted store (custom subsystems may need `log config … --mode persist:debug`).

```bash
slog stream --signpost --subsystem com.myapp --category perf --capture 10s
```

**Other:** `slog profile create|list|show|delete <name>` (saved filter combos, apply with `--profile`) · `slog list processes|simulators` · `slog doctor` · `slog mcp [--setup]`.

## MCP reference

Tools: `slog_show`, `slog_stream`, `slog_signpost`, `slog_list_processes`, `slog_list_simulators`, `slog_doctor`. Per-arg/response schemas live in each tool's own description — this is just the workflow layer on top.

- **The five workflow rules apply unchanged.** `subsystem`/`process`/`category` are JSON arrays (OR-matched, exact case). MCP has no `info`/`debug` flag, so set `subsystem` (auto-debug) or `level: "debug"` to surface debug, and use `slog_stream` for it (`slog_show` can't replay debug).
- **Large results spill to `output_file`** (NDJSON) — read it with `Read offset/limit` or `jq`, never slurp. `full: true` inlines everything; `slog_show`'s `summary_only: true` answers "how many / what kinds".
- **Iterate cheaply:** pass a prior `output_file` back as `slog_show.source_file` to re-filter without rescanning the OS DB. **Tail:** pass `next_since` back as the next `start`.
- **`slog_signpost`** returns aggregated interval stats; use `live: true` for the no-persistence path right after exercising the app.
- **On 0 results or errors:** read the `hint`, and call `slog_doctor` whenever a payload carries `try_doctor: true`.

## Troubleshooting: "the logs aren't showing up"

Walk in order:

1. **Code uses `os_log`/`os.Logger`?** If it's `print`/`NSLog`/stdout/stderr → not capturable; fix the source.
2. **Filtering `--process` only, missing debug/info?** No auto-debug there — add `--subsystem`, or set `--level debug`/`info`.
3. **Using `show`/`slog_show` for debug?** Debug isn't persisted — use `stream`/`slog_stream`, or `log config … --mode persist:debug`.
4. **Want signpost timings?** Add `--signpost` / use `slog_signpost` (`live: true`).
5. **Values show `<private>`?** Working as intended — add `privacy: .public` at the call site.
6. **Still nothing?** `slog doctor` / `slog_doctor` (permissions, log CLI); for MCP read `hint`/`try_doctor`.

## Reference

- **Levels** (least→most severe): `debug` < `info` < `default` < `error` < `fault`. `--level` is a **minimum** (`error` ⇒ error+fault). `Logger.notice` ⇒ `default`; `.warning`/`.critical` ⇒ `error`/`fault` — there is **no** `--level notice`.
- **Formats:** `color` (default) · `plain` · `compact` (ts+level+msg) · `json` (NDJSON, `| jq`) · `toon` (fewest tokens). **Prefer `toon`/token-cheap MCP modes for agent workflows.**
- **Exit codes:** `0` = capture complete / interrupted · `1` = timeout or stream error.
- **Misc:** `--dedup` collapses repeats into "message (xN)"; `--source` adds file/function/line; `--last boot` = since last boot.
