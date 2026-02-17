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
        let multiplier: Double
        let numberString: String

        switch lastChar {
        case "s", "S":
            multiplier = 1.0
            numberString = String(trimmed.dropLast())
        case "m", "M":
            multiplier = 60.0
            numberString = String(trimmed.dropLast())
        case "h", "H":
            multiplier = 3600.0
            numberString = String(trimmed.dropLast())
        default:
            multiplier = 1.0
            numberString = trimmed
        }

        guard let value = Double(numberString), value > 0 else {
            throw ValidationError(
                "\(optionName) must be a positive number with optional suffix (s, m, h). Got: \(string)"
            )
        }

        return value * multiplier
    }
}
