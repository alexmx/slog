//
//  FilterChain.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation

/// A chain of filters that processes log entries
public struct FilterChain: Sendable {
    private var predicates: [any LogPredicate] = []

    public init() {}

    /// Add a predicate to the filter chain
    public mutating func add(_ predicate: any LogPredicate) {
        predicates.append(predicate)
    }

    /// Add a process name filter
    @discardableResult
    public mutating func process(_ name: String) -> FilterChain {
        add(ProcessNamePredicate(processName: name))
        return self
    }

    /// Add a process ID filter
    @discardableResult
    public mutating func pid(_ pid: Int) -> FilterChain {
        add(ProcessIDPredicate(pid: pid))
        return self
    }

    /// Add a subsystem filter
    @discardableResult
    public mutating func subsystem(_ subsystem: String, matchPrefix: Bool = false) -> FilterChain {
        add(SubsystemPredicate(subsystem: subsystem, matchPrefix: matchPrefix))
        return self
    }

    /// Add a category filter
    @discardableResult
    public mutating func category(_ category: String) -> FilterChain {
        add(CategoryPredicate(category: category))
        return self
    }

    /// Add a minimum log level filter
    @discardableResult
    public mutating func minimumLevel(_ level: LogLevel) -> FilterChain {
        add(MinimumLevelPredicate(minimumLevel: level))
        return self
    }

    /// Add a message substring filter
    @discardableResult
    public mutating func messageContains(_ substring: String) -> FilterChain {
        add(MessageContainsPredicate(substring: substring))
        return self
    }

    /// Add a regex filter on the message
    @discardableResult
    public mutating func messageRegex(_ pattern: String) throws -> FilterChain {
        add(try MessageRegexPredicate(pattern: pattern))
        return self
    }

    /// Add an exclusion regex filter on the message (NOT match)
    @discardableResult
    public mutating func excludeMessageRegex(_ pattern: String) throws -> FilterChain {
        add(NotPredicate(try MessageRegexPredicate(pattern: pattern)))
        return self
    }

    /// Test if an entry passes all filters
    public func matches(_ entry: LogEntry) -> Bool {
        predicates.allSatisfy { $0.matches(entry) }
    }

    /// Filter a sequence of entries
    public func filter(_ entries: [LogEntry]) -> [LogEntry] {
        entries.filter { matches($0) }
    }

    /// Remove all predicates
    public mutating func clear() {
        predicates.removeAll()
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
