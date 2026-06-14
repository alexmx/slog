//
//  FilterTests.swift
//  slog
//
//  Created by Alex Maimescu on 02/02/2026.
//

import Foundation
@testable import slog
import Testing

@Suite("Filter Predicate Tests")
struct FilterPredicateTests {
    /// Helper to create a test log entry
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

    @Test
    func processNamePredicate() {
        let predicate = ProcessNamePredicate(processName: "testapp")
        let entry = makeEntry(processName: "TestApp")

        #expect(predicate.matches(entry) == true)
    }

    @Test
    func processNamePredicateCaseSensitive() {
        let predicate = ProcessNamePredicate(processName: "TestApp", caseSensitive: true)

        #expect(predicate.matches(makeEntry(processName: "TestApp")) == true)
        #expect(predicate.matches(makeEntry(processName: "testapp")) == false)
    }

    @Test
    func processIDPredicate() {
        let predicate = ProcessIDPredicate(pid: 1234)

        #expect(predicate.matches(makeEntry(pid: 1234)) == true)
        #expect(predicate.matches(makeEntry(pid: 5678)) == false)
    }

    @Test
    func subsystemPredicateExact() {
        let predicate = SubsystemPredicate(subsystem: "com.test.app")

        #expect(predicate.matches(makeEntry(subsystem: "com.test.app")) == true)
        #expect(predicate.matches(makeEntry(subsystem: "com.test.other")) == false)
        #expect(predicate.matches(makeEntry(subsystem: nil)) == false)
    }

    @Test
    func subsystemPredicatePrefix() {
        let predicate = SubsystemPredicate(subsystem: "com.test", matchPrefix: true)

        #expect(predicate.matches(makeEntry(subsystem: "com.test.app")) == true)
        #expect(predicate.matches(makeEntry(subsystem: "com.test.other")) == true)
        #expect(predicate.matches(makeEntry(subsystem: "com.other")) == false)
    }

    @Test
    func minimumLevelPredicate() {
        let predicate = MinimumLevelPredicate(minimumLevel: .error)

        #expect(predicate.matches(makeEntry(level: .debug)) == false)
        #expect(predicate.matches(makeEntry(level: .info)) == false)
        #expect(predicate.matches(makeEntry(level: .default)) == false)
        #expect(predicate.matches(makeEntry(level: .error)) == true)
        #expect(predicate.matches(makeEntry(level: .fault)) == true)
    }

    @Test
    func messageRegexPredicate() throws {
        let predicate = try MessageRegexPredicate(pattern: "error.*timeout")

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

    @Test
    func emptyChainMatchesAll() {
        let chain = FilterChain()
        let entry = makeEntry()

        #expect(chain.isEmpty == true)
        #expect(chain.matches(entry) == true)
    }

    @Test
    func chainCombinesWithAnd() {
        var chain = FilterChain()
        chain.process("TestApp")
        chain.minimumLevel(.error)

        #expect(chain.matches(makeEntry(processName: "TestApp", level: .error)) == true)
        #expect(chain.matches(makeEntry(processName: "TestApp", level: .info)) == false)
        #expect(chain.matches(makeEntry(processName: "OtherApp", level: .error)) == false)
    }

    @Test
    func chainBuilder() {
        var chain = FilterChain()
        chain.process("MyApp")
        chain.subsystem("com.my.app")
        chain.minimumLevel(.info)

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

    @Test
    func chainFiltersArray() {
        var chain = FilterChain()
        chain.minimumLevel(.error)

        let entries = [
            makeEntry(level: .debug),
            makeEntry(level: .info),
            makeEntry(level: .error),
            makeEntry(level: .fault)
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

    @Test
    func notPredicate() {
        let predicate = NotPredicate(MinimumLevelPredicate(minimumLevel: .error))

        #expect(predicate.matches(makeEntry(level: .error)) == false)
        #expect(predicate.matches(makeEntry(level: .fault)) == false)
        #expect(predicate.matches(makeEntry(level: .info)) == true)
    }
}
