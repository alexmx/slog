//
//  Predicates.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation

/// A predicate that can filter log entries
public protocol LogPredicate: Sendable {
    /// Returns true if the entry matches this predicate
    func matches(_ entry: LogEntry) -> Bool
}

// MARK: - Process Predicates

/// Matches entries from a specific process name
public struct ProcessNamePredicate: LogPredicate {
    public let processName: String
    public let caseSensitive: Bool

    public init(processName: String, caseSensitive: Bool = false) {
        self.processName = processName
        self.caseSensitive = caseSensitive
    }

    public func matches(_ entry: LogEntry) -> Bool {
        if caseSensitive {
            entry.processName == processName
        } else {
            entry.processName.lowercased() == processName.lowercased()
        }
    }
}

/// Matches entries from a specific process ID
public struct ProcessIDPredicate: LogPredicate {
    public let pid: Int

    public init(pid: Int) {
        self.pid = pid
    }

    public func matches(_ entry: LogEntry) -> Bool {
        entry.pid == pid
    }
}

// MARK: - Subsystem Predicates

/// Matches entries with a specific subsystem
public struct SubsystemPredicate: LogPredicate {
    public let subsystem: String
    public let matchPrefix: Bool

    public init(subsystem: String, matchPrefix: Bool = false) {
        self.subsystem = subsystem
        self.matchPrefix = matchPrefix
    }

    public func matches(_ entry: LogEntry) -> Bool {
        guard let entrySubsystem = entry.subsystem else { return false }

        if matchPrefix {
            return entrySubsystem.hasPrefix(subsystem)
        } else {
            return entrySubsystem == subsystem
        }
    }
}

/// Matches entries with a specific category
public struct CategoryPredicate: LogPredicate {
    public let category: String

    public init(category: String) {
        self.category = category
    }

    public func matches(_ entry: LogEntry) -> Bool {
        entry.category == category
    }
}

// MARK: - Level Predicates

/// Matches entries at or above a minimum log level
public struct MinimumLevelPredicate: LogPredicate {
    public let minimumLevel: LogLevel

    public init(minimumLevel: LogLevel) {
        self.minimumLevel = minimumLevel
    }

    public func matches(_ entry: LogEntry) -> Bool {
        entry.level >= minimumLevel
    }
}

/// Matches entries at exactly a specific log level
public struct ExactLevelPredicate: LogPredicate {
    public let level: LogLevel

    public init(level: LogLevel) {
        self.level = level
    }

    public func matches(_ entry: LogEntry) -> Bool {
        entry.level == level
    }
}

// MARK: - Message Predicates

/// Matches entries where the message contains a substring
public struct MessageContainsPredicate: LogPredicate {
    public let substring: String
    public let caseSensitive: Bool

    public init(substring: String, caseSensitive: Bool = false) {
        self.substring = substring
        self.caseSensitive = caseSensitive
    }

    public func matches(_ entry: LogEntry) -> Bool {
        if caseSensitive {
            entry.message.contains(substring)
        } else {
            entry.message.lowercased().contains(substring.lowercased())
        }
    }
}

/// Matches entries where the message matches a regular expression
public struct MessageRegexPredicate: LogPredicate {
    private let regex: NSRegularExpression

    public init(pattern: String, caseSensitive: Bool = false) throws {
        var options: NSRegularExpression.Options = []
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }
        regex = try NSRegularExpression(pattern: pattern, options: options)
    }

    public func matches(_ entry: LogEntry) -> Bool {
        let range = NSRange(entry.message.startIndex..., in: entry.message)
        return regex.firstMatch(in: entry.message, options: [], range: range) != nil
    }
}

// MARK: - Composite Predicates

/// Matches entries that match ALL of the given predicates (AND)
public struct AllOfPredicate: LogPredicate {
    public let predicates: [any LogPredicate]

    public init(predicates: [any LogPredicate]) {
        self.predicates = predicates
    }

    public func matches(_ entry: LogEntry) -> Bool {
        predicates.allSatisfy { $0.matches(entry) }
    }
}

/// Matches entries that match ANY of the given predicates (OR)
public struct AnyOfPredicate: LogPredicate {
    public let predicates: [any LogPredicate]

    public init(predicates: [any LogPredicate]) {
        self.predicates = predicates
    }

    public func matches(_ entry: LogEntry) -> Bool {
        predicates.contains { $0.matches(entry) }
    }
}

/// Inverts the result of another predicate (NOT)
public struct NotPredicate: LogPredicate {
    public let predicate: any LogPredicate

    public init(_ predicate: any LogPredicate) {
        self.predicate = predicate
    }

    public func matches(_ entry: LogEntry) -> Bool {
        !predicate.matches(entry)
    }
}

// MARK: - Always/Never Predicates

/// Always matches (passes all entries through)
public struct AlwaysPredicate: LogPredicate {
    public init() {}

    public func matches(_: LogEntry) -> Bool {
        true
    }
}

/// Never matches (filters out all entries)
public struct NeverPredicate: LogPredicate {
    public init() {}

    public func matches(_: LogEntry) -> Bool {
        false
    }
}
