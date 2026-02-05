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
    public mutating func messageRegex(_ pattern: String) -> FilterChain {
        add(MessageRegexPredicate(pattern: pattern))
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

    /// Build a filter chain using a closure-based DSL
    public static func build(_ configure: (inout FilterChainBuilder) -> Void) -> FilterChain {
        var builder = FilterChainBuilder()
        configure(&builder)
        return builder.build()
    }
}

// MARK: - Filter Chain Builder

/// DSL for building filter chains
public struct FilterChainBuilder {
    private var predicates: [any LogPredicate] = []

    public init() {}

    public mutating func process(_ name: String) {
        predicates.append(ProcessNamePredicate(processName: name))
    }

    public mutating func pid(_ pid: Int) {
        predicates.append(ProcessIDPredicate(pid: pid))
    }

    public mutating func subsystem(_ subsystem: String, matchPrefix: Bool = false) {
        predicates.append(SubsystemPredicate(subsystem: subsystem, matchPrefix: matchPrefix))
    }

    public mutating func category(_ category: String) {
        predicates.append(CategoryPredicate(category: category))
    }

    public mutating func minimumLevel(_ level: LogLevel) {
        predicates.append(MinimumLevelPredicate(minimumLevel: level))
    }

    public mutating func messageContains(_ substring: String) {
        predicates.append(MessageContainsPredicate(substring: substring))
    }

    public mutating func messageRegex(_ pattern: String) {
        predicates.append(MessageRegexPredicate(pattern: pattern))
    }

    public func build() -> FilterChain {
        var chain = FilterChain()
        for predicate in predicates {
            chain.add(predicate)
        }
        return chain
    }
}

