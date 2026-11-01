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
        self.decoder = JSONDecoder()
    }

    /// Parse a single NDJSON line into a LogEntry
    public func parse(line: String) -> LogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let data = Data(trimmed.utf8)
        if let rawEntry = try? decoder.decode(RawLogEntry.self, from: data) {
            return rawEntry.toLogEntry()
        }
        // Fall back to legacy format if JSON fails
        return parseLegacyFormat(line: trimmed)
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

        guard let timestamp = LogTimestamp.parse(timestampString) else {
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
           let subsystemRange = Range(subsystemMatch.range(at: 1), in: messageRemainder) {
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
           let levelRange = Range(levelMatch.range(at: 1), in: messageRemainder) {
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
    let subsystem: String?
    let category: String?
    let messageType: String?
    let eventType: String?
    let eventMessage: String?
    let activityIdentifier: Int?
    let threadID: Int?
    let traceID: Int?
    let source: SourceInfo?
    let signpostID: UInt64?
    let signpostName: String?
    let signpostType: String?
    let signpostScope: String?

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
            source: source?.formatted(),
            signpostID: signpostID,
            signpostName: signpostName,
            signpostType: signpostType.flatMap(SignpostType.init(string:)),
            signpostScope: signpostScope
        )
    }

    private func parseTimestamp(_ string: String) -> Date {
        LogTimestamp.parse(string) ?? Date()
    }
}

// MARK: - Timestamp Parsing

/// Parses `log` timestamps (`2026-06-26 13:23:32.715547+0100` or ISO 8601)
/// without losing sub-millisecond precision.
///
/// `DateFormatter` and `ISO8601DateFormatter` truncate fractional seconds to
/// milliseconds, which collapses sub-ms signpost durations to 0 or 1ms. So the
/// fraction is split off, the rest is parsed at whole-second precision, and the
/// fraction is added back as a `Double`.
enum LogTimestamp {
    /// Formatters are expensive to create; `date(from:)` and `string(from:)`
    /// are thread-safe. UTC, whole seconds.
    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let appleFormatters: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ssZ",
        "yyyy-MM-dd HH:mm:ssZZZZ"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    static func parse(_ string: String) -> Date? {
        let (wholeSeconds, fraction) = splitFraction(string)
        let date = isoFormatter.date(from: wholeSeconds)
            ?? appleFormatters.lazy.compactMap { $0.date(from: wholeSeconds) }.first
        return date?.addingTimeInterval(fraction)
    }

    /// ISO 8601 in UTC with microseconds, e.g. `2026-11-01T19:34:54.123456Z`.
    /// Foundation's `.iso8601` JSON strategy drops the fraction entirely.
    static func format(_ date: Date) -> String {
        let interval = date.timeIntervalSince1970
        var seconds = interval.rounded(.down)
        var micros = Int(((interval - seconds) * 1_000_000).rounded())
        if micros == 1_000_000 {
            seconds += 1
            micros = 0
        }
        let wholeSeconds = isoFormatter.string(from: Date(timeIntervalSince1970: seconds))
        return wholeSeconds.dropLast() + String(format: ".%06dZ", micros)
    }

    /// `date` as whole seconds in UTC (`2026-11-01 22:07:07+0000`), the only
    /// precision `log show --start/--end` accepts; rounded down or up.
    static func wholeSecondArgument(_ date: Date, roundingUp: Bool) -> String {
        let seconds = date.timeIntervalSince1970
        let whole = roundingUp ? seconds.rounded(.up) : seconds.rounded(.down)
        return logArgumentFormatter.string(from: Date(timeIntervalSince1970: whole))
    }

    private static let logArgumentFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        return formatter
    }()

    /// JSON date strategies for every encoder/decoder slog uses, so timestamps
    /// keep microseconds. Decoding also accepts whole-second values.
    static let jsonEncoding = JSONEncoder.DateEncodingStrategy.custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(format(date))
    }

    static let jsonDecoding = JSONDecoder.DateDecodingStrategy.custom { decoder in
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = parse(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp: \(string)")
        }
        return date
    }

    /// Splits `"…:32.715547+0100"` into `("…:32+0100", 0.715547)`.
    private static func splitFraction(_ string: String) -> (String, TimeInterval) {
        guard let dot = string.firstIndex(of: ".") else { return (string, 0) }
        let digitsStart = string.index(after: dot)
        let digitsEnd = string[digitsStart...].firstIndex { !("0"..."9").contains($0) } ?? string.endIndex
        guard digitsStart < digitsEnd,
              let fraction = TimeInterval("0." + string[digitsStart..<digitsEnd])
        else { return (string, 0) }
        return (String(string[..<dot] + string[digitsEnd...]), fraction)
    }
}
