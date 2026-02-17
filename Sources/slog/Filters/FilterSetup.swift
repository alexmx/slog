//
//  FilterSetup.swift
//  slog
//

import Foundation

/// Consolidated result of building server-side predicates, client-side filter chain,
/// and log level inclusion from shared filter parameters.
public struct FilterSetup: Sendable {
    /// Server-side predicate string for `log stream/show --predicate`
    public let predicate: String?

    /// Client-side filter chain for grep/excludeGrep patterns
    public let filterChain: FilterChain

    /// Whether info-level messages should be included
    public let includeInfo: Bool

    /// Whether debug-level messages should be included
    public let includeDebug: Bool

    /// Build a FilterSetup from common filter parameters.
    ///
    /// Consolidates PredicateBuilder, FilterChain grep/excludeGrep, and auto-debug logic.
    /// Auto-debug: when subsystem is set without explicit level or info/debug flags,
    /// debug and info messages are automatically included.
    public static func build(
        process: String? = nil,
        pid: Int? = nil,
        subsystem: String? = nil,
        category: String? = nil,
        level: LogLevel? = nil,
        grep: String? = nil,
        excludeGrep: String? = nil,
        info: Bool = false,
        debug: Bool = false
    ) -> FilterSetup {
        let predicate = PredicateBuilder.buildPredicate(
            process: process,
            pid: pid,
            subsystem: subsystem,
            category: category,
            level: level
        )

        var filterChain = FilterChain()
        if let grep {
            filterChain.messageRegex(grep)
        }
        if let excludeGrep {
            filterChain.excludeMessageRegex(excludeGrep)
        }

        let autoDebug = subsystem != nil && level == nil && !info && !debug
        let includeDebug = debug || autoDebug
        let includeInfo = info || includeDebug

        return FilterSetup(
            predicate: predicate,
            filterChain: filterChain,
            includeInfo: includeInfo,
            includeDebug: includeDebug
        )
    }
}
