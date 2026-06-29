//
// slog-test-emitter
//
// Emits a known set of log entries via Apple's unified logging system.
// Use this to test slog commands and filters against predictable output.
//
// Usage:
//   swift run slog-test-emitter              # Emit all test logs once
//   swift run slog-test-emitter --repeat 5   # Repeat 5 times (1s interval)
//   swift run slog-test-emitter --continuous  # Emit every second until interrupted
//

import Foundation
import os

// MARK: - Loggers

let defaultLogger = Logger(subsystem: "com.slog.test", category: "general")
let networkLogger = Logger(subsystem: "com.slog.test.network", category: "http")
let databaseLogger = Logger(subsystem: "com.slog.test.database", category: "query")
let authLogger = Logger(subsystem: "com.slog.test", category: "auth")
let performanceLogger = Logger(subsystem: "com.slog.test", category: "performance")

/// Signposter for os_signpost interval testing (separate from os_log messages).
let signposter = OSSignposter(subsystem: "com.slog.test", category: "signpost")

// MARK: - Log Emission

func emitTestLogs(batch: Int) {
    let prefix = batch > 0 ? "[batch-\(batch)] " : ""

    // Default level
    defaultLogger.log("\(prefix, privacy: .public)Application started successfully")
    defaultLogger.log("\(prefix, privacy: .public)Configuration loaded from defaults")

    // Info level
    defaultLogger.info("\(prefix, privacy: .public)User session initialized with token abc-123")
    networkLogger.info("\(prefix, privacy: .public)DNS resolved api.example.com to 93.184.216.34")

    // Debug level
    defaultLogger.debug("\(prefix, privacy: .public)Cache hit ratio: 0.87 (hits=174, misses=26)")
    databaseLogger.debug("\(prefix, privacy: .public)Query plan: sequential scan on users WHERE active=true")
    performanceLogger.debug("\(prefix, privacy: .public)Frame render time: 16.2ms (target: 16.6ms)")

    // Error level
    authLogger.error("\(prefix, privacy: .public)Authentication failed: invalid credentials for user@example.com")
    networkLogger.error("\(prefix, privacy: .public)Connection timeout after 30s to api.example.com:443")
    databaseLogger.error("\(prefix, privacy: .public)Deadlock detected on table 'orders', retrying transaction")

    // Fault level
    defaultLogger.fault("\(prefix, privacy: .public)Out of memory: failed to allocate 256MB buffer")
    networkLogger.fault("\(prefix, privacy: .public)TLS handshake failed: certificate expired for api.example.com")

    // Messages with special patterns (for grep/exclude-grep testing)
    defaultLogger.log("\(prefix, privacy: .public)heartbeat: system healthy, uptime 3d 14h 22m")
    defaultLogger.log("\(prefix, privacy: .public)heartbeat: all services responding")
    networkLogger.log("\(prefix, privacy: .public)GET /api/v1/users -> 200 OK (42ms)")
    networkLogger.log("\(prefix, privacy: .public)POST /api/v1/orders -> 201 Created (128ms)")
    networkLogger.log("\(prefix, privacy: .public)GET /api/v1/health -> 200 OK (2ms)")
    databaseLogger.log("\(prefix, privacy: .public)SELECT * FROM users WHERE id=42 -- 1 row (0.3ms)")
    databaseLogger
        .log("\(prefix, privacy: .public)INSERT INTO audit_log (action, user_id) VALUES ('login', 42) -- 1 row (1.2ms)")

    // Messages with unicode and special characters
    defaultLogger.log("\(prefix, privacy: .public)User 'José García' logged in from São Paulo")
    defaultLogger.log("\(prefix, privacy: .public)Processing file: report_2026-Q1_final (v2).pdf")
}

// MARK: - Signpost Emission

//
// Emits os_signpost *intervals* (begin/end pairs) — a different substrate than
// os_log messages. Each interval is two separate log events sharing
// (subsystem, category, name, signpostID); the consumer pairs begin->end by ID
// and computes duration = end.ts - begin.ts.
//
// Covers the three cases a pairing implementation must handle:
//   1. Simple sequential interval with interpolated args.
//   2. Two CONCURRENT same-name intervals with distinct IDs (must NOT collapse).
//   3. An in-flight begin with no matching end (duration should be null).
// Plus a standalone signpost event (not an interval).

func emitSignposts(batch: Int) {
    let suffix = batch > 0 ? " batch=\(batch)" : ""

    // 1. Sequential interval with args.
    let id1 = signposter.makeSignpostID()
    let s1 = signposter.beginInterval(
        "parse.postImage",
        id: id1,
        "len \(208_123, privacy: .public)\(suffix, privacy: .public)"
    )
    Thread.sleep(forTimeInterval: 0.04)
    signposter.endInterval("parse.postImage", s1)

    // 2. Concurrent same-name intervals, distinct IDs, overlapping lifetimes.
    let idA = signposter.makeSignpostID()
    let idB = signposter.makeSignpostID()
    let a = signposter.beginInterval("attr.chunk", id: idA, "start \(0, privacy: .public)\(suffix, privacy: .public)")
    let b = signposter.beginInterval(
        "attr.chunk",
        id: idB,
        "start \(4096, privacy: .public)\(suffix, privacy: .public)"
    )
    Thread.sleep(forTimeInterval: 0.010)
    signposter.endInterval("attr.chunk", a)
    Thread.sleep(forTimeInterval: 0.005)
    signposter.endInterval("attr.chunk", b)

    // 3. In-flight begin: intentionally never ended (state dropped).
    let id3 = signposter.makeSignpostID()
    _ = signposter.beginInterval("render.draw", id: id3, "frame \(1, privacy: .public)\(suffix, privacy: .public)")

    // Standalone signpost event (not an interval).
    signposter.emitEvent("checkpoint", "phase init\(suffix, privacy: .public)")
}

let entriesPerBatch = 21

// MARK: - Smoke Test (logging-mechanism visibility)

///
/// Emits exactly one line through every distinct Apple logging mechanism, each
/// tagged `SMOKE|<nonce>|<id>` so a harness can grep which mechanisms are visible
/// to slog / the unified log and which are not. The nonce isolates a single run.
///
/// Mechanisms grouped by substrate:
///   - stdout/stderr  : print, debugPrint, FileHandle.standardError, fputs — NOT
///                      part of unified logging (slog can never see these).
///   - NSLog          : bridges to unified logging, but with NO subsystem/category.
///   - os_log (C API) : default/info/debug/error/fault via OSLog object.
///   - os.Logger      : trace/debug/info/notice/warning/error/critical/fault.
///   - privacy        : default-private interpolation (redaction) vs .public.
///   - os_signpost    : interval begin/end + standalone event (need --signpost).
///
func emitSmoke(nonce: String) {
    func tag(_ id: String) -> String {
        "SMOKE|\(nonce)|\(id)"
    }

    // --- stdout / stderr (NOT part of unified logging) ---
    print(tag("print_stdout"))
    debugPrint(tag("debugprint_stdout"))
    FileHandle.standardError.write(Data((tag("filehandle_stderr") + "\n").utf8))
    fputs(tag("fputs_stderr") + "\n", stderr)

    // --- NSLog (bridges to unified logging; empty subsystem/category) ---
    NSLog("%@", tag("nslog"))

    // --- os_log C API (subsystem com.slog.smoke, category oslog) ---
    let osLog = OSLog(subsystem: "com.slog.smoke", category: "oslog")
    os_log("%{public}@", log: osLog, type: .default, tag("oslog_default"))
    os_log("%{public}@", log: osLog, type: .info, tag("oslog_info"))
    os_log("%{public}@", log: osLog, type: .debug, tag("oslog_debug"))
    os_log("%{public}@", log: osLog, type: .error, tag("oslog_error"))
    os_log("%{public}@", log: osLog, type: .fault, tag("oslog_fault"))

    // --- os.Logger (subsystem com.slog.smoke, category logger) ---
    let logger = Logger(subsystem: "com.slog.smoke", category: "logger")
    logger.trace("\(tag("logger_trace"), privacy: .public)")
    logger.debug("\(tag("logger_debug"), privacy: .public)")
    logger.info("\(tag("logger_info"), privacy: .public)")
    logger.notice("\(tag("logger_notice"), privacy: .public)")
    logger.warning("\(tag("logger_warning"), privacy: .public)")
    logger.error("\(tag("logger_error"), privacy: .public)")
    logger.critical("\(tag("logger_critical"), privacy: .public)")
    logger.fault("\(tag("logger_fault"), privacy: .public)")

    // --- Privacy / redaction (interpolated values are private by default) ---
    let secret = "SECRET-\(nonce)"
    logger.log("\(tag("logger_private"), privacy: .public) value=\(secret)")
    logger.log("\(tag("logger_public"), privacy: .public) value=\(secret, privacy: .public)")

    // --- os_signpost (interval + event; need --signpost to surface) ---
    let smokeSignposter = OSSignposter(subsystem: "com.slog.smoke", category: "signpost")
    let sid = smokeSignposter.makeSignpostID()
    let state = smokeSignposter.beginInterval("smoke.interval", id: sid, "\(tag("signpost_begin"), privacy: .public)")
    Thread.sleep(forTimeInterval: 0.01)
    smokeSignposter.endInterval("smoke.interval", state)
    smokeSignposter.emitEvent("smoke.event", "\(tag("signpost_event"), privacy: .public)")
}

// MARK: - CLI

let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    print("""
    slog-test-emitter - Emit test logs for slog testing
    
    Usage:
      slog-test-emitter                 Emit all test logs once
      slog-test-emitter --repeat N      Repeat N times (1s interval)
      slog-test-emitter --continuous    Emit every second until Ctrl+C
      slog-test-emitter --signpost      Emit os_signpost intervals instead of os_log messages
                                        (combine with --repeat / --continuous)
      slog-test-emitter --smoke NONCE   Emit one tagged line per logging mechanism
                                        (print/NSLog/os_log/Logger/signpost) for the
                                        logging-visibility smoke test, then exit
    
    Subsystems emitted:
      com.slog.test              (categories: general, auth, performance)
      com.slog.test.network      (category: http)
      com.slog.test.database     (category: query)
    
    Log levels emitted: debug, info, default, error, fault
    """)
    exit(0)
}

// Smoke mode: emit one tagged line per logging mechanism, then exit.
if let idx = args.firstIndex(of: "--smoke") {
    let nonce = (idx + 1 < args.count && !args[idx + 1].hasPrefix("--")) ? args[idx + 1] : "nononce"
    emitSmoke(nonce: nonce)
    print("Smoke emit complete (nonce=\(nonce))")
    exit(0)
}

let continuous = args.contains("--continuous")
let signpostMode = args.contains("--signpost")
var repeatCount = 1

if let idx = args.firstIndex(of: "--repeat"), idx + 1 < args.count,
   let count = Int(args[idx + 1]) {
    repeatCount = count
}

/// Emit one batch of the active mode (signposts or os_log messages).
func emitBatch(_ batch: Int) {
    if signpostMode {
        emitSignposts(batch: batch)
    } else {
        emitTestLogs(batch: batch)
    }
}

if continuous {
    let kind = signpostMode ? "signpost intervals" : "test logs"
    print("Emitting \(kind) continuously (Ctrl+C to stop)...")
    var batch = 1
    while true {
        emitBatch(batch)
        print("  Batch \(batch) emitted")
        batch += 1
        Thread.sleep(forTimeInterval: 1.0)
    }
} else if signpostMode {
    for i in 0..<repeatCount {
        emitSignposts(batch: repeatCount > 1 ? i + 1 : 0)
        if repeatCount > 1 {
            print("  Batch \(i + 1) emitted")
            if i < repeatCount - 1 { Thread.sleep(forTimeInterval: 1.0) }
        }
    }
    print("Emitted signpost intervals (parse.postImage, attr.chunk x2 concurrent, render.draw in-flight) + 1 event")
    print("")
    print("Capture intervals with the OS log CLI (signposts are skipped without --signpost):")
    print("  log show --last 30s --signpost --style ndjson --predicate 'subsystem == \"com.slog.test\"'")
    print("  log stream --signpost --style ndjson --predicate 'subsystem == \"com.slog.test\"'")
} else {
    for i in 0..<repeatCount {
        emitTestLogs(batch: repeatCount > 1 ? i + 1 : 0)
        if repeatCount > 1 {
            print("  Batch \(i + 1) emitted")
            if i < repeatCount - 1 {
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }
    print("Emitted \(entriesPerBatch * repeatCount) test log entries")
    print("")
    print("Test with slog:")
    print("  slog show --last 10s --subsystem com.slog.test")
    print("  slog show --last 10s --subsystem com.slog.test --level error")
    print("  slog show --last 10s --subsystem com.slog.test --category auth")
    print("  slog show --last 10s --subsystem com.slog.test --grep heartbeat")
    print("  slog show --last 10s --subsystem com.slog.test --exclude-grep heartbeat")
    print("  slog show --last 10s --subsystem com.slog.test --format json")
    print("  slog show --last 10s --subsystem com.slog.test --format compact")
    print("  slog show --last 10s --subsystem com.slog.test --format toon")
    print("")
    print("Stream test (run emitter with --continuous in another terminal):")
    print("  slog stream --subsystem com.slog.test")
    print("  slog stream --subsystem com.slog.test --level error")
    print("  slog stream --subsystem com.slog.test.network --category http")
    print("  slog stream --subsystem com.slog.test --grep 'api.*users'")
    print("  slog stream --subsystem com.slog.test --exclude-grep heartbeat")
    print("  slog stream --subsystem com.slog.test --count 5")
}
