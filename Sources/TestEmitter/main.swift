///
/// slog-test-emitter
///
/// Emits a known set of log entries via Apple's unified logging system.
/// Use this to test slog commands and filters against predictable output.
///
/// Usage:
///   swift run slog-test-emitter              # Emit all test logs once
///   swift run slog-test-emitter --repeat 5   # Repeat 5 times (1s interval)
///   swift run slog-test-emitter --continuous  # Emit every second until interrupted
///

import Foundation
import os

// MARK: - Loggers

let defaultLogger = Logger(subsystem: "com.slog.test", category: "general")
let networkLogger = Logger(subsystem: "com.slog.test.network", category: "http")
let databaseLogger = Logger(subsystem: "com.slog.test.database", category: "query")
let authLogger = Logger(subsystem: "com.slog.test", category: "auth")
let performanceLogger = Logger(subsystem: "com.slog.test", category: "performance")

// MARK: - Log Emission

func emitTestLogs(batch: Int) {
    let prefix = batch > 0 ? "[batch-\(batch)] " : ""

    // Default level
    defaultLogger.log("\(prefix)Application started successfully")
    defaultLogger.log("\(prefix)Configuration loaded from defaults")

    // Info level
    defaultLogger.info("\(prefix)User session initialized with token abc-123")
    networkLogger.info("\(prefix)DNS resolved api.example.com to 93.184.216.34")

    // Debug level
    defaultLogger.debug("\(prefix)Cache hit ratio: 0.87 (hits=174, misses=26)")
    databaseLogger.debug("\(prefix)Query plan: sequential scan on users WHERE active=true")
    performanceLogger.debug("\(prefix)Frame render time: 16.2ms (target: 16.6ms)")

    // Error level
    authLogger.error("\(prefix)Authentication failed: invalid credentials for user@example.com")
    networkLogger.error("\(prefix)Connection timeout after 30s to api.example.com:443")
    databaseLogger.error("\(prefix)Deadlock detected on table 'orders', retrying transaction")

    // Fault level
    defaultLogger.fault("\(prefix)Out of memory: failed to allocate 256MB buffer")
    networkLogger.fault("\(prefix)TLS handshake failed: certificate expired for api.example.com")

    // Messages with special patterns (for grep/exclude-grep testing)
    defaultLogger.log("\(prefix)heartbeat: system healthy, uptime 3d 14h 22m")
    defaultLogger.log("\(prefix)heartbeat: all services responding")
    networkLogger.log("\(prefix)GET /api/v1/users -> 200 OK (42ms)")
    networkLogger.log("\(prefix)POST /api/v1/orders -> 201 Created (128ms)")
    networkLogger.log("\(prefix)GET /api/v1/health -> 200 OK (2ms)")
    databaseLogger.log("\(prefix)SELECT * FROM users WHERE id=42 -- 1 row (0.3ms)")
    databaseLogger.log("\(prefix)INSERT INTO audit_log (action, user_id) VALUES ('login', 42) -- 1 row (1.2ms)")

    // Messages with unicode and special characters
    defaultLogger.log("\(prefix)User 'José García' logged in from São Paulo")
    defaultLogger.log("\(prefix)Processing file: report_2026-Q1_final (v2).pdf")
}

let entriesPerBatch = 21

// MARK: - CLI

let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    print("""
    slog-test-emitter - Emit test logs for slog testing

    Usage:
      slog-test-emitter                 Emit all test logs once
      slog-test-emitter --repeat N      Repeat N times (1s interval)
      slog-test-emitter --continuous    Emit every second until Ctrl+C

    Subsystems emitted:
      com.slog.test              (categories: general, auth, performance)
      com.slog.test.network      (category: http)
      com.slog.test.database     (category: query)

    Log levels emitted: debug, info, default, error, fault
    """)
    exit(0)
}

let continuous = args.contains("--continuous")
var repeatCount = 1

if let idx = args.firstIndex(of: "--repeat"), idx + 1 < args.count,
   let count = Int(args[idx + 1])
{
    repeatCount = count
}

if continuous {
    print("Emitting test logs continuously (Ctrl+C to stop)...")
    var batch = 1
    while true {
        emitTestLogs(batch: batch)
        print("  Batch \(batch) emitted (\(entriesPerBatch) log entries)")
        batch += 1
        Thread.sleep(forTimeInterval: 1.0)
    }
} else {
    for i in 0 ..< repeatCount {
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
