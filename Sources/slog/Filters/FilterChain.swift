//
//  FilterChain.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation

/// Predicates applied to log entries client-side; an entry must match all of them.
public struct FilterChain: Sendable {
    private var predicates: [any LogPredicate] = []

    public init() {}

    /// Add a predicate to the filter chain
    public mutating func add(_ predicate: any LogPredicate) {
        predicates.append(predicate)
    }

    /// Add a process ID filter
    public mutating func pid(_ pid: Int) {
        add(ProcessIDPredicate(pid: pid))
    }

    /// Add a minimum log level filter
    public mutating func minimumLevel(_ level: LogLevel) {
        add(MinimumLevelPredicate(minimumLevel: level))
    }

    /// Add a regex filter on the message
    public mutating func messageRegex(_ pattern: String) throws {
        try add(MessageRegexPredicate(pattern: pattern))
    }

    /// Add an exclusion regex filter on the message (NOT match)
    public mutating func excludeMessageRegex(_ pattern: String) throws {
        try add(NotPredicate(MessageRegexPredicate(pattern: pattern)))
    }

    /// Test if an entry passes all filters. An empty chain matches everything.
    public func matches(_ entry: LogEntry) -> Bool {
        predicates.allSatisfy { $0.matches(entry) }
    }

    /// Check if the chain has any predicates
    public var isEmpty: Bool {
        predicates.isEmpty
    }

    /// Number of predicates in the chain
    public var count: Int {
        predicates.count
    }
}
