//
//  LogParser.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation

/// Parses log stream output (NDJSON format) into LogEntry structs
public struct LogParser: Sendable {
    private let decoder: JSONDecoder

    public init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds first
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // Try without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // Try Apple's log format: "2024-01-15 10:30:45.123456-0800"
            let appleFormatter = DateFormatter()
            appleFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
            if let date = appleFormatter.date(from: dateString) {
                return date
            }

            appleFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZ"
            if let date = appleFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string: \(dateString)"
            )
        }
    }

    /// Parse a single NDJSON line into a LogEntry
    public func parse(line: String) -> LogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = trimmed.data(using: .utf8) else { return nil }

        do {
            let rawEntry = try decoder.decode(RawLogEntry.self, from: data)
            return rawEntry.toLogEntry()
        } catch {
            // Try parsing as legacy format if JSON fails
            return parseLegacyFormat(line: trimmed)
        }
    }

    /// Parse multiple lines (e.g., from a buffer)
    public func parseLines(_ text: String) -> [LogEntry] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parse(line: String($0)) }
    }

    // MARK: - Legacy Format Parsing

    /// Parse the traditional `log stream` output format
    /// Example: "2024-01-15 10:30:45.123456-0800  Finder[1234]  (com.apple.finder) [Info]  Message here"
    private func parseLegacyFormat(line: String) -> LogEntry? {
        // This is a basic parser for non-JSON output
        // The actual format can vary, so this handles common patterns

        // Try to extract timestamp at the beginning
        let timestampPattern = #"^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+[+-]\d{4})"#

        guard let timestampRegex = try? NSRegularExpression(pattern: timestampPattern),
              let timestampMatch = timestampRegex.firstMatch(
                  in: line,
                  range: NSRange(line.startIndex..., in: line)
              ),
              let timestampRange = Range(timestampMatch.range(at: 1), in: line)
        else {
            return nil
        }

        let timestampString = String(line[timestampRange])
        let remainder = String(line[timestampRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Parse timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        guard let timestamp = dateFormatter.date(from: timestampString) else {
            return nil
        }

        // Try to extract process name and PID: "ProcessName[PID]"
        let processPattern = #"^(\S+)\[(\d+)\]"#
        guard let processRegex = try? NSRegularExpression(pattern: processPattern),
              let processMatch = processRegex.firstMatch(
                  in: remainder,
                  range: NSRange(remainder.startIndex..., in: remainder)
              ),
              let nameRange = Range(processMatch.range(at: 1), in: remainder),
              let pidRange = Range(processMatch.range(at: 2), in: remainder),
              let pid = Int(remainder[pidRange])
        else {
            // If we can't parse process info, create a basic entry
            return LogEntry(
                timestamp: timestamp,
                processName: "unknown",
                pid: 0,
                subsystem: nil,
                category: nil,
                level: .default,
                message: remainder
            )
        }

        let processName = String(remainder[nameRange])
        var messageRemainder = String(remainder[pidRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)

        // Remove leading ']' if present
        if messageRemainder.hasPrefix("]") {
            messageRemainder = String(messageRemainder.dropFirst())
                .trimmingCharacters(in: .whitespaces)
        }

        // Try to extract subsystem: "(com.example.subsystem)"
        var subsystem: String?
        let subsystemPattern = #"^\(([^)]+)\)"#
        if let subsystemRegex = try? NSRegularExpression(pattern: subsystemPattern),
           let subsystemMatch = subsystemRegex.firstMatch(
               in: messageRemainder,
               range: NSRange(messageRemainder.startIndex..., in: messageRemainder)
           ),
           let subsystemRange = Range(subsystemMatch.range(at: 1), in: messageRemainder)
        {
            subsystem = String(messageRemainder[subsystemRange])
            if let fullRange = Range(subsystemMatch.range, in: messageRemainder) {
                messageRemainder = String(messageRemainder[fullRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Try to extract log level: "[Info]", "[Error]", etc.
        var level = LogLevel.default
        let levelPattern = #"^\[(\w+)\]"#
        if let levelRegex = try? NSRegularExpression(pattern: levelPattern),
           let levelMatch = levelRegex.firstMatch(
               in: messageRemainder,
               range: NSRange(messageRemainder.startIndex..., in: messageRemainder)
           ),
           let levelRange = Range(levelMatch.range(at: 1), in: messageRemainder)
        {
            let levelString = String(messageRemainder[levelRange])
            level = LogLevel(string: levelString) ?? .default
            if let fullRange = Range(levelMatch.range, in: messageRemainder) {
                messageRemainder = String(messageRemainder[fullRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        return LogEntry(
            timestamp: timestamp,
            processName: processName,
            pid: pid,
            subsystem: subsystem,
            category: nil,
            level: level,
            message: messageRemainder
        )
    }
}

// MARK: - Raw JSON Entry

/// Represents the raw JSON structure from `log stream --style ndjson`
private struct RawLogEntry: Decodable {
    let timestamp: String
    let processImagePath: String?
    let processID: Int?
    let senderImagePath: String?
    let senderProgramCounter: Int?
    let machTimestamp: Int?
    let subsystem: String?
    let category: String?
    let messageType: String?
    let eventType: String?
    let eventMessage: String?
    let activityIdentifier: Int?
    let parentActivityIdentifier: Int?
    let threadID: Int?
    let traceID: Int?
    let processUniqueID: Int?
    let processImageUUID: String?
    let senderImageUUID: String?
    let creatorActivityID: Int?
    let source: SourceInfo?
    let backtrace: BacktraceInfo?

    struct SourceInfo: Decodable {
        let symbol: String?
        let file: String?
        let line: Int?
        let image: String?

        /// Format source info into a human-readable string
        func formatted() -> String? {
            var parts: [String] = []

            if let image, !image.isEmpty {
                parts.append(image)
            }

            if let symbol, !symbol.isEmpty {
                parts.append(symbol)
            }

            if let file, !file.isEmpty {
                if let line, line > 0 {
                    parts.append("\(file):\(line)")
                } else {
                    parts.append(file)
                }
            }

            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }

    struct BacktraceInfo: Decodable {
        let frames: [FrameInfo]?

        struct FrameInfo: Decodable {
            let imageOffset: Int?
            let imageUUID: String?
        }
    }

    func toLogEntry() -> LogEntry {
        // Parse timestamp
        let timestamp = parseTimestamp(timestamp)

        // Extract process name from path
        let processName: String = if let path = processImagePath {
            URL(fileURLWithPath: path).lastPathComponent
        } else {
            "unknown"
        }

        // Parse log level from messageType
        let level: LogLevel = if let messageType {
            LogLevel(string: messageType) ?? .default
        } else {
            .default
        }

        return LogEntry(
            timestamp: timestamp,
            processName: processName,
            pid: processID ?? 0,
            subsystem: subsystem,
            category: category,
            level: level,
            message: eventMessage ?? "",
            threadID: threadID,
            activityID: activityIdentifier,
            traceID: traceID,
            processImagePath: processImagePath,
            senderImagePath: senderImagePath,
            eventType: eventType,
            source: source?.formatted()
        )
    }

    private func parseTimestamp(_ string: String) -> Date {
        // Try ISO8601 formats
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        // Try Apple's log format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        if let date = dateFormatter.date(from: string) {
            return date
        }

        return Date()
    }
}
