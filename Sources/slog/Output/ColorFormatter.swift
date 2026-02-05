//
//  ColorFormatter.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation
import Rainbow

/// Colored output formatter using ANSI colors
public struct ColorFormatter: LogFormatter {
    private let showTimestamp: Bool
    private let showLevel: Bool
    private let showProcess: Bool
    private let showSubsystem: Bool
    private let highlightPattern: String?
    private let timestampFormatter: TimestampFormatter

    public init(
        showTimestamp: Bool = true,
        showLevel: Bool = true,
        showProcess: Bool = true,
        showSubsystem: Bool = true,
        highlightPattern: String? = nil,
        timestampFormatter: TimestampFormatter = TimestampFormatter()
    ) {
        self.showTimestamp = showTimestamp
        self.showLevel = showLevel
        self.showProcess = showProcess
        self.showSubsystem = showSubsystem
        self.highlightPattern = highlightPattern
        self.timestampFormatter = timestampFormatter
    }

    public func format(_ entry: LogEntry) -> String {
        var components: [String] = []

        if showTimestamp {
            let timestamp = timestampFormatter.format(entry.timestamp)
            components.append(timestamp.lightBlack)
        }

        if showLevel {
            let levelStr = coloredLevel(entry.level)
            components.append(levelStr)
        }

        if showProcess {
            let processStr = "\(entry.processName)[\(entry.pid)]"
            components.append(processStr.cyan)
        }

        if showSubsystem, let subsystem = entry.subsystem {
            let subsystemStr: String
            if let category = entry.category {
                subsystemStr = "(\(subsystem):\(category))"
            } else {
                subsystemStr = "(\(subsystem))"
            }
            components.append(subsystemStr.lightBlack)
        }

        var message = entry.message

        // Highlight pattern matches if specified
        if let pattern = highlightPattern,
           let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            message = highlightMatches(in: message, regex: regex)
        }

        // Color message based on level
        let coloredMessage = colorMessage(message, level: entry.level)
        components.append(coloredMessage)

        return components.joined(separator: " ")
    }

    private func coloredLevel(_ level: LogLevel) -> String {
        let levelStr: String
        let colored: String

        switch level {
        case .debug:
            levelStr = "DEBUG"
            colored = levelStr.lightBlack
        case .info:
            levelStr = "INFO"
            colored = levelStr.blue
        case .default:
            levelStr = "DEFAULT"
            colored = levelStr.white
        case .error:
            levelStr = "ERROR"
            colored = levelStr.red.bold
        case .fault:
            levelStr = "FAULT"
            colored = levelStr.red.bold.blink
        }

        return "[\(colored)]"
    }

    private func colorMessage(_ message: String, level: LogLevel) -> String {
        switch level {
        case .debug:
            return message.lightBlack
        case .info:
            return message
        case .default:
            return message
        case .error:
            return message.red
        case .fault:
            return message.red.bold
        }
    }

    private func highlightMatches(in text: String, regex: NSRegularExpression) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        guard !matches.isEmpty else { return text }

        var result = text
        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            if let swiftRange = Range(match.range, in: result) {
                let matchedText = String(result[swiftRange])
                let highlighted = matchedText.yellow.bold.underline
                result.replaceSubrange(swiftRange, with: highlighted)
            }
        }

        return result
    }
}
