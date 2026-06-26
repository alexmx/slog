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
    /// `processes`, `subsystems`, and `categories` accept multiple values that are
    /// OR-grouped in the resulting predicate. Pass already-parsed arrays — callers
    /// dealing with comma-separated CLI/profile strings should run `splitCSV` first.
    ///
    /// Consolidates PredicateBuilder, FilterChain grep/excludeGrep, and auto-debug logic.
    /// Auto-debug: when a subsystem is set without explicit level or info/debug flags,
    /// debug and info messages are automatically included.
    public static func build(
        processes: [String] = [],
        pid: Int? = nil,
        subsystems: [String] = [],
        categories: [String] = [],
        level: LogLevel? = nil,
        grep: String? = nil,
        excludeGrep: String? = nil,
        info: Bool = false,
        debug: Bool = false,
        signpost: Bool = false
    ) throws -> FilterSetup {
        let predicate = PredicateBuilder.buildPredicate(
            processes: processes,
            pid: pid,
            subsystems: subsystems,
            categories: categories,
            level: level,
            signpostOnly: signpost
        )

        // Field filters go into the FilterChain too — redundant on the live
        // path (server-side predicate already filtered) but the only enforcement
        // on the `source_file` replay path. Cost is microseconds per entry.
        var filterChain = FilterChain()
        if !processes.isEmpty {
            filterChain.add(AnyOfPredicate(processes.map { ProcessNamePredicate(processName: $0) }))
        }
        if let pid {
            filterChain.pid(pid)
        }
        if !subsystems.isEmpty {
            // BEGINSWITH mirrors the server-side predicate so child subsystems match.
            filterChain.add(AnyOfPredicate(subsystems.map { SubsystemPredicate(subsystem: $0, matchPrefix: true) }))
        }
        if !categories.isEmpty {
            filterChain.add(AnyOfPredicate(categories.map { CategoryPredicate(category: $0) }))
        }
        if let level {
            filterChain.minimumLevel(level)
        }
        if let grep {
            do { try filterChain.messageRegex(grep) }
            catch { throw FilterSetupError.invalidRegex(field: "grep", reason: error.localizedDescription) }
        }
        if let excludeGrep {
            do { try filterChain.excludeMessageRegex(excludeGrep) }
            catch { throw FilterSetupError.invalidRegex(field: "exclude_grep", reason: error.localizedDescription) }
        }

        // Signpost mode includes info+debug so debug-scoped signposts surface.
        let autoDebug = signpost || (!subsystems.isEmpty && level == nil && !info && !debug)
        let includeDebug = debug || autoDebug
        let includeInfo = info || includeDebug

        return FilterSetup(
            predicate: predicate,
            filterChain: filterChain,
            includeInfo: includeInfo,
            includeDebug: includeDebug
        )
    }

    /// Split a comma-separated string into trimmed, non-empty tokens.
    /// Used by callers (CLI, profile loader) that receive raw user input as `String?`.
    public static func splitCSV(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw.split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

public enum FilterSetupError: Error, LocalizedError {
    case invalidRegex(field: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidRegex(let field, let reason):
            "Invalid '\(field)' regex: \(reason)"
        }
    }
}
