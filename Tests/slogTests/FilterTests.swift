//
//  FilterTests.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Testing
import Foundation
@testable import slog

@Suite("Filter Predicate Tests")
struct FilterPredicateTests {
    // Helper to create a test log entry
    func makeEntry(
        processName: String = "TestApp",
        pid: Int = 1234,
        subsystem: String? = "com.test.app",
        category: String? = "default",
        level: LogLevel = .info,
        message: String = "Test message"
    ) -> LogEntry {
        LogEntry(
            timestamp: Date(),
            processName: processName,
            pid: pid,
            subsystem: subsystem,
            category: category,
            level: level,
            message: message
        )
    }

    @Test("ProcessNamePredicate matches process name case-insensitively")
    func processNamePredicate() {
        let predicate = ProcessNamePredicate(processName: "testapp")
        let entry = makeEntry(processName: "TestApp")

        #expect(predicate.matches(entry) == true)
    }

    @Test("ProcessNamePredicate case-sensitive matching")
    func processNamePredicateCaseSensitive() {
        let predicate = ProcessNamePredicate(processName: "TestApp", caseSensitive: true)

        #expect(predicate.matches(makeEntry(processName: "TestApp")) == true)
        #expect(predicate.matches(makeEntry(processName: "testapp")) == false)
    }

    @Test("ProcessIDPredicate matches PID")
    func processIDPredicate() {
        let predicate = ProcessIDPredicate(pid: 1234)

        #expect(predicate.matches(makeEntry(pid: 1234)) == true)
        #expect(predicate.matches(makeEntry(pid: 5678)) == false)
    }

    @Test("SubsystemPredicate matches exact subsystem")
    func subsystemPredicateExact() {
        let predicate = SubsystemPredicate(subsystem: "com.test.app")

        #expect(predicate.matches(makeEntry(subsystem: "com.test.app")) == true)
        #expect(predicate.matches(makeEntry(subsystem: "com.test.other")) == false)
        #expect(predicate.matches(makeEntry(subsystem: nil)) == false)
    }

    @Test("SubsystemPredicate matches prefix")
    func subsystemPredicatePrefix() {
        let predicate = SubsystemPredicate(subsystem: "com.test", matchPrefix: true)

        #expect(predicate.matches(makeEntry(subsystem: "com.test.app")) == true)
        #expect(predicate.matches(makeEntry(subsystem: "com.test.other")) == true)
        #expect(predicate.matches(makeEntry(subsystem: "com.other")) == false)
    }

    @Test("MinimumLevelPredicate filters by level")
    func minimumLevelPredicate() {
        let predicate = MinimumLevelPredicate(minimumLevel: .error)

        #expect(predicate.matches(makeEntry(level: .debug)) == false)
        #expect(predicate.matches(makeEntry(level: .info)) == false)
        #expect(predicate.matches(makeEntry(level: .default)) == false)
        #expect(predicate.matches(makeEntry(level: .error)) == true)
        #expect(predicate.matches(makeEntry(level: .fault)) == true)
    }

    @Test("MessageContainsPredicate matches substring")
    func messageContainsPredicate() {
        let predicate = MessageContainsPredicate(substring: "error")

        #expect(predicate.matches(makeEntry(message: "An error occurred")) == true)
        #expect(predicate.matches(makeEntry(message: "An ERROR occurred")) == true)
        #expect(predicate.matches(makeEntry(message: "Success")) == false)
    }

    @Test("MessageRegexPredicate matches pattern")
    func messageRegexPredicate() {
        let predicate = MessageRegexPredicate(pattern: "error.*timeout")

        #expect(predicate.matches(makeEntry(message: "error: connection timeout")) == true)
        #expect(predicate.matches(makeEntry(message: "Error with timeout")) == true)
        #expect(predicate.matches(makeEntry(message: "timeout error")) == false) // Order matters
    }
}

@Suite("FilterChain Tests")
struct FilterChainTests {
    func makeEntry(
        processName: String = "TestApp",
        pid: Int = 1234,
        subsystem: String? = "com.test.app",
        level: LogLevel = .info,
        message: String = "Test message"
    ) -> LogEntry {
        LogEntry(
            timestamp: Date(),
            processName: processName,
            pid: pid,
            subsystem: subsystem,
            category: nil,
            level: level,
            message: message
        )
    }

    @Test("Empty filter chain matches all entries")
    func emptyChainMatchesAll() {
        let chain = FilterChain()
        let entry = makeEntry()

        #expect(chain.isEmpty == true)
        #expect(chain.matches(entry) == true)
    }

    @Test("Filter chain combines predicates with AND logic")
    func chainCombinesWithAnd() {
        var chain = FilterChain()
        chain.filterByProcess("TestApp")
        chain.filterByMinimumLevel(.error)

        #expect(chain.matches(makeEntry(processName: "TestApp", level: .error)) == true)
        #expect(chain.matches(makeEntry(processName: "TestApp", level: .info)) == false)
        #expect(chain.matches(makeEntry(processName: "OtherApp", level: .error)) == false)
    }

    @Test("Filter chain builder DSL")
    func chainBuilder() {
        let chain = buildFilterChain { builder in
            builder.process("MyApp")
            builder.subsystem("com.my.app")
            builder.minimumLevel(.info)
        }

        #expect(chain.count == 3)

        let matchingEntry = LogEntry(
            timestamp: Date(),
            processName: "MyApp",
            pid: 1,
            subsystem: "com.my.app",
            category: nil,
            level: .info,
            message: "Test"
        )

        #expect(chain.matches(matchingEntry) == true)
    }

    @Test("Filter chain filters array of entries")
    func chainFiltersArray() {
        var chain = FilterChain()
        chain.filterByMinimumLevel(.error)

        let entries = [
            makeEntry(level: .debug),
            makeEntry(level: .info),
            makeEntry(level: .error),
            makeEntry(level: .fault),
        ]

        let filtered = chain.filter(entries)

        #expect(filtered.count == 2)
        #expect(filtered[0].level == .error)
        #expect(filtered[1].level == .fault)
    }
}

@Suite("Composite Predicate Tests")
struct CompositePredicateTests {
    func makeEntry(level: LogLevel = .info, message: String = "Test") -> LogEntry {
        LogEntry(
            timestamp: Date(),
            processName: "Test",
            pid: 1,
            subsystem: nil,
            category: nil,
            level: level,
            message: message
        )
    }

    @Test("AllOfPredicate requires all to match")
    func allOfPredicate() {
        let predicate = AllOfPredicate(predicates: [
            MinimumLevelPredicate(minimumLevel: .error),
            MessageContainsPredicate(substring: "critical"),
        ])

        #expect(predicate.matches(makeEntry(level: .error, message: "critical error")) == true)
        #expect(predicate.matches(makeEntry(level: .error, message: "normal error")) == false)
        #expect(predicate.matches(makeEntry(level: .info, message: "critical info")) == false)
    }

    @Test("AnyOfPredicate requires any to match")
    func anyOfPredicate() {
        let predicate = AnyOfPredicate(predicates: [
            ExactLevelPredicate(level: .error),
            ExactLevelPredicate(level: .fault),
        ])

        #expect(predicate.matches(makeEntry(level: .error)) == true)
        #expect(predicate.matches(makeEntry(level: .fault)) == true)
        #expect(predicate.matches(makeEntry(level: .info)) == false)
    }

    @Test("NotPredicate inverts result")
    func notPredicate() {
        let predicate = NotPredicate(ExactLevelPredicate(level: .debug))

        #expect(predicate.matches(makeEntry(level: .debug)) == false)
        #expect(predicate.matches(makeEntry(level: .info)) == true)
        #expect(predicate.matches(makeEntry(level: .error)) == true)
    }
}
