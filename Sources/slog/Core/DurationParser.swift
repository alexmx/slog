//
//  DurationParser.swift
//  slog
//

import ArgumentParser
import Foundation

/// Parses human-readable duration strings (e.g., "5s", "2m", "1h") into TimeInterval
enum DurationParser {
    /// Parse a duration string like "5s", "2m", "1h" into seconds.
    /// A bare number without suffix is treated as seconds.
    static func parse(_ string: String, optionName: String) throws -> TimeInterval {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard let lastChar = trimmed.last else {
            throw ValidationError("\(optionName) cannot be empty")
        }

        let (multiplier, numberString): (Double, String) = switch lastChar {
        case "s", "S": (1, String(trimmed.dropLast()))
        case "m", "M": (60, String(trimmed.dropLast()))
        case "h", "H": (3600, String(trimmed.dropLast()))
        default: (1, trimmed)
        }

        guard let value = Double(numberString), value > 0 else {
            throw ValidationError(
                "\(optionName) must be a positive number with optional suffix (s, m, h). Got: \(string)"
            )
        }

        return value * multiplier
    }
}
