//
//  LogStreamer.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation

/// Configuration for log streaming
public struct StreamConfiguration: Sendable {
    /// Target for log streaming
    public enum Target: Sendable {
        /// Stream from the local macOS system
        case local
        /// Stream from an iOS Simulator with the given UDID
        case simulator(udid: String)
    }

    /// The target to stream logs from
    public let target: Target

    /// Server-side predicate for filtering (passed to `log stream --predicate`)
    public let predicate: String?

    /// Whether to include info-level messages
    public let includeInfo: Bool

    /// Whether to include debug-level messages
    public let includeDebug: Bool

    public init(
        target: Target = .local,
        predicate: String? = nil,
        includeInfo: Bool = true,
        includeDebug: Bool = false
    ) {
        self.target = target
        self.predicate = predicate
        self.includeInfo = includeInfo
        self.includeDebug = includeDebug
    }
}

/// Manages spawning and reading from `log stream` process
public final class LogStreamer: @unchecked Sendable {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private let parser: LogParser
    private var isRunning = false
    private let lock = NSLock()

    /// Callback for each parsed log entry
    public var onEntry: (@Sendable (LogEntry) -> Void)?

    /// Callback for raw lines (useful for debugging)
    public var onRawLine: (@Sendable (String) -> Void)?

    /// Callback for errors
    public var onError: (@Sendable (Error) -> Void)?

    /// Callback when streaming stops
    public var onStop: (@Sendable () -> Void)?

    public init() {
        self.parser = LogParser()
    }

    /// Start streaming logs with the given configuration
    public func start(configuration: StreamConfiguration) throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else {
            throw StreamerError.alreadyRunning
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        // Configure based on target
        switch configuration.target {
        case .local:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = buildArguments(for: configuration)

        case .simulator(let udid):
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "spawn", udid, "log"] + buildArguments(for: configuration)
        }

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set up output handling
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let string = String(data: data, encoding: .utf8) {
                self?.handleOutput(string)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let string = String(data: data, encoding: .utf8) {
                self?.handleError(string)
            }
        }

        // Handle process termination
        process.terminationHandler = { [weak self] _ in
            self?.handleTermination()
        }

        try process.run()

        self.process = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        self.isRunning = true
    }

    /// Stop the log stream
    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning else { return }

        process?.terminate()
        cleanup()
    }

    /// Check if currently streaming
    public var running: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    // MARK: - Private

    private func buildArguments(for configuration: StreamConfiguration) -> [String] {
        var args = ["stream", "--style", "ndjson"]

        if configuration.includeInfo {
            args.append("--info")
        }

        if configuration.includeDebug {
            args.append("--debug")
        }

        if let predicate = configuration.predicate {
            args.append("--predicate")
            args.append(predicate)
        }

        return args
    }

    private func handleOutput(_ string: String) {
        // Split into lines and process each
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let lineString = String(line)
            guard !lineString.isEmpty else { continue }

            onRawLine?(lineString)

            if let entry = parser.parse(line: lineString) {
                onEntry?(entry)
            }
        }
    }

    private func handleError(_ string: String) {
        let error = StreamerError.logStreamError(string.trimmingCharacters(in: .whitespacesAndNewlines))
        onError?(error)
    }

    private func handleTermination() {
        lock.lock()
        cleanup()
        lock.unlock()

        onStop?()
    }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        errorPipe = nil
        process = nil
        isRunning = false
    }
}

// MARK: - Errors

public enum StreamerError: Error, LocalizedError {
    case alreadyRunning
    case logStreamError(String)
    case simulatorNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Log streamer is already running"
        case .logStreamError(let message):
            return "Log stream error: \(message)"
        case .simulatorNotFound(let udid):
            return "Simulator not found: \(udid)"
        }
    }
}

// MARK: - Predicate Builder

/// Builds predicates for the `log stream --predicate` option
public struct PredicateBuilder: Sendable {
    private var components: [String] = []

    public init() {}

    /// Filter by process name
    public mutating func process(_ name: String) {
        components.append("processImagePath ENDSWITH \"/\(name)\"")
    }

    /// Filter by process ID
    public mutating func pid(_ pid: Int) {
        components.append("processID == \(pid)")
    }

    /// Filter by subsystem
    public mutating func subsystem(_ subsystem: String) {
        components.append("subsystem == \"\(subsystem)\"")
    }

    /// Filter by category
    public mutating func category(_ category: String) {
        components.append("category == \"\(category)\"")
    }

    /// Filter by minimum log level
    public mutating func level(_ level: LogLevel) {
        let levelValue: Int
        switch level {
        case .debug:
            levelValue = 0
        case .info:
            levelValue = 1
        case .default:
            levelValue = 2
        case .error:
            levelValue = 16
        case .fault:
            levelValue = 17
        }
        components.append("messageType >= \(levelValue)")
    }

    /// Filter by message content (contains)
    public mutating func messageContains(_ text: String) {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        components.append("eventMessage CONTAINS \"\(escaped)\"")
    }

    /// Build the final predicate string
    public func build() -> String? {
        guard !components.isEmpty else { return nil }
        return components.joined(separator: " AND ")
    }

    /// Create a predicate from common filter options
    public static func from(
        process: String? = nil,
        pid: Int? = nil,
        subsystem: String? = nil,
        category: String? = nil,
        level: LogLevel? = nil
    ) -> String? {
        var builder = PredicateBuilder()

        if let process = process {
            builder.process(process)
        }
        if let pid = pid {
            builder.pid(pid)
        }
        if let subsystem = subsystem {
            builder.subsystem(subsystem)
        }
        if let category = category {
            builder.category(category)
        }
        if let level = level {
            builder.level(level)
        }

        return builder.build()
    }
}
