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
    private let showProcess: Bool
    private let showSubsystem: Bool
    /// Compiled once; nil when there is no pattern or it does not compile.
    private let highlightRegex: NSRegularExpression?
    private let timestampFormatter: TimestampFormatter

    public init(
        showProcess: Bool = true,
        showSubsystem: Bool = true,
        highlightPattern: String? = nil,
        timestampFormatter: TimestampFormatter = TimestampFormatter()
    ) {
        self.showProcess = showProcess
        self.showSubsystem = showSubsystem
        self.highlightRegex = highlightPattern.flatMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
        self.timestampFormatter = timestampFormatter
    }

    public func format(_ entry: LogEntry) -> String {
        var components = [
            timestampFormatter.format(entry.timestamp).lightBlack,
            coloredLevel(entry.level)
        ]

        if showProcess {
            let processStr = "\(entry.processName)[\(entry.pid)]"
            components.append(processStr.cyan)
        }

        if showSubsystem, let subsystem = entry.subsystem {
            let subsystemStr = if let category = entry.category {
                "(\(subsystem):\(category))"
            } else {
                "(\(subsystem))"
            }
            components.append(subsystemStr.lightBlack)
        }

        var message = entry.message

        // Highlight pattern matches if specified
        if let highlightRegex {
            message = highlightMatches(in: message, regex: highlightRegex)
        }

        // Color message based on level
        let coloredMessage = colorMessage(message, level: entry.level)
        components.append(coloredMessage)

        return components.joined(separator: " ")
    }

    private func coloredLevel(_ level: LogLevel) -> String {
        let text = level.rawValue.uppercased()
        let colored: String = switch level {
        case .debug: text.lightBlack
        case .info: text.blue
        case .default: text.white
        case .error: text.red.bold
        case .fault: text.red.bold.blink
        }
        return "[\(colored)]"
    }

    private func colorMessage(_ message: String, level: LogLevel) -> String {
        switch level {
        case .debug: message.lightBlack
        case .info, .default: message
        case .error: message.red
        case .fault: message.red.bold
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
