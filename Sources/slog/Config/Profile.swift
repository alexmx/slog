//
//  Profile.swift
//  slog
//

import Foundation

/// A saved set of filter and format options that can be loaded by name.
/// All fields are optional — only specified fields affect the command.
public struct Profile: Codable, Equatable, Sendable {
    /// Filter by process name
    public var process: String?

    /// Filter by process ID
    public var pid: Int?

    /// Filter by subsystem
    public var subsystem: String?

    /// Filter by category
    public var category: String?

    /// Minimum log level (debug, info, default, error, fault)
    public var level: String?

    /// Filter messages by regex pattern
    public var grep: String?

    /// Output format (plain, compact, color, json, toon)
    public var format: String?

    /// Timestamp mode (absolute, relative)
    public var time: String?

    /// Include info-level messages
    public var info: Bool?

    /// Include debug-level messages
    public var debug: Bool?

    /// Include source location info
    public var source: Bool?

    /// Stream from iOS Simulator
    public var simulator: Bool?

    /// Simulator UDID
    public var simulatorUDID: String?

    public init(
        process: String? = nil,
        pid: Int? = nil,
        subsystem: String? = nil,
        category: String? = nil,
        level: String? = nil,
        grep: String? = nil,
        format: String? = nil,
        time: String? = nil,
        info: Bool? = nil,
        debug: Bool? = nil,
        source: Bool? = nil,
        simulator: Bool? = nil,
        simulatorUDID: String? = nil
    ) {
        self.process = process
        self.pid = pid
        self.subsystem = subsystem
        self.category = category
        self.level = level
        self.grep = grep
        self.format = format
        self.time = time
        self.info = info
        self.debug = debug
        self.source = source
        self.simulator = simulator
        self.simulatorUDID = simulatorUDID
    }

    /// Whether the profile has no fields set
    public var isEmpty: Bool {
        process == nil && pid == nil && subsystem == nil && category == nil &&
        level == nil && grep == nil && format == nil && time == nil && info == nil &&
        debug == nil && source == nil && simulator == nil && simulatorUDID == nil
    }

    /// Resolve the level string to a LogLevel, if valid
    public var resolvedLevel: LogLevel? {
        level.flatMap { LogLevel(string: $0) }
    }

    /// Resolve the format string to an OutputFormat, if valid
    public var resolvedFormat: OutputFormat? {
        format.flatMap { OutputFormat(rawValue: $0) }
    }

    /// Resolve the time string to a TimeMode, if valid
    public var resolvedTimeMode: TimeMode? {
        time.flatMap { TimeMode(rawValue: $0) }
    }
}
