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
            entry.processName.caseInsensitiveCompare(processName) == .orderedSame
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

// MARK: - Message Predicates

/// Matches entries where the message matches a regular expression
public struct MessageRegexPredicate: LogPredicate {
    private let regex: NSRegularExpression

    public init(pattern: String, caseSensitive: Bool = false) throws {
        var options: NSRegularExpression.Options = []
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }
        self.regex = try NSRegularExpression(pattern: pattern, options: options)
    }

    public func matches(_ entry: LogEntry) -> Bool {
        let range = NSRange(entry.message.startIndex..., in: entry.message)
        return regex.firstMatch(in: entry.message, options: [], range: range) != nil
    }
}

// MARK: - Composite Predicates

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
