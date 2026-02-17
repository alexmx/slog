//
//  FormattedEntry.swift
//  slog
//

import Foundation

/// Shared Encodable model for structured output formats (JSON, TOON).
/// Maps LogEntry fields to a flat, serializable structure.
public struct FormattedEntry: Encodable, Sendable {
    public let timestamp: Date
    public let process: String
    public let pid: Int
    public let level: String
    public let message: String
    public let subsystem: String?
    public let category: String?
    public let threadID: Int?
    public let activityID: Int?
    public let processImagePath: String?
    public let senderImagePath: String?
    public let traceID: Int?
    public let eventType: String?
    public let source: String?

    public init(from entry: LogEntry) {
        timestamp = entry.timestamp
        process = entry.processName
        pid = entry.pid
        level = entry.level.rawValue
        message = entry.message
        subsystem = entry.subsystem
        category = entry.category
        threadID = entry.threadID
        activityID = entry.activityID
        traceID = entry.traceID
        processImagePath = entry.processImagePath
        senderImagePath = entry.senderImagePath
        eventType = entry.eventType
        source = entry.source
    }
}
