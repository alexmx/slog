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
        self.timestamp = entry.timestamp
        self.process = entry.processName
        self.pid = entry.pid
        self.level = entry.level.rawValue
        self.message = entry.message
        self.subsystem = entry.subsystem
        self.category = entry.category
        self.threadID = entry.threadID
        self.activityID = entry.activityID
        self.traceID = entry.traceID
        self.processImagePath = entry.processImagePath
        self.senderImagePath = entry.senderImagePath
        self.eventType = entry.eventType
        self.source = entry.source
    }
}
