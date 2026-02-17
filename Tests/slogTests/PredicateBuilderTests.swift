//
//  PredicateBuilderTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("PredicateBuilder Tests")
struct PredicateBuilderTests {
    // MARK: - Individual Predicates

    @Test("Process predicate uses ENDSWITH")
    func processFilter() {
        var builder = PredicateBuilder()
        builder.process("Finder")
        let predicate = builder.build()

        #expect(predicate == "processImagePath ENDSWITH \"/Finder\"")
    }

    @Test("PID predicate uses equality")
    func pidFilter() {
        var builder = PredicateBuilder()
        builder.pid(1234)
        let predicate = builder.build()

        #expect(predicate == "processID == 1234")
    }

    @Test("Subsystem predicate uses equality")
    func subsystemFilter() {
        var builder = PredicateBuilder()
        builder.subsystem("com.apple.network")
        let predicate = builder.build()

        #expect(predicate == "subsystem == \"com.apple.network\"")
    }

    @Test("Category predicate uses equality")
    func categoryFilter() {
        var builder = PredicateBuilder()
        builder.category("http")
        let predicate = builder.build()

        #expect(predicate == "category == \"http\"")
    }

    @Test("Level predicate uses messageType with correct values",
          arguments: [
              (LogLevel.debug, 0),
              (LogLevel.info, 1),
              (LogLevel.default, 2),
              (LogLevel.error, 16),
              (LogLevel.fault, 17),
          ])
    func levelFilter(level: LogLevel, value: Int) {
        var builder = PredicateBuilder()
        builder.level(level)
        let predicate = builder.build()

        #expect(predicate == "messageType >= \(value)")
    }

    @Test("Message contains predicate uses CONTAINS")
    func messageContainsFilter() {
        var builder = PredicateBuilder()
        builder.messageContains("error")
        let predicate = builder.build()

        #expect(predicate == "eventMessage CONTAINS \"error\"")
    }

    @Test("Message contains escapes quotes")
    func messageContainsEscapesQuotes() {
        var builder = PredicateBuilder()
        builder.messageContains("say \"hello\"")
        let predicate = builder.build()

        #expect(predicate == "eventMessage CONTAINS \"say \\\"hello\\\"\"")
    }

    @Test("Message contains escapes backslashes before quotes")
    func messageContainsEscapesBackslashes() {
        var builder = PredicateBuilder()
        builder.messageContains("path\\to\\file")
        let predicate = builder.build()

        #expect(predicate == "eventMessage CONTAINS \"path\\\\to\\\\file\"")
    }

    // MARK: - Combinations

    @Test("Multiple predicates joined with AND")
    func multiplePredicates() {
        var builder = PredicateBuilder()
        builder.process("MyApp")
        builder.subsystem("com.my.app")
        let predicate = builder.build()

        #expect(predicate?.contains(" AND ") == true)
        #expect(predicate?.contains("processImagePath ENDSWITH \"/MyApp\"") == true)
        #expect(predicate?.contains("subsystem == \"com.my.app\"") == true)
    }

    @Test("Empty builder returns nil")
    func emptyBuilder() {
        let builder = PredicateBuilder()
        let predicate = builder.build()

        #expect(predicate == nil)
    }

    // MARK: - Static Helper

    @Test("buildPredicate with all parameters")
    func buildPredicateAllParams() {
        let predicate = PredicateBuilder.buildPredicate(
            process: "MyApp",
            pid: 42,
            subsystem: "com.my.app",
            category: "net",
            level: .error
        )

        #expect(predicate != nil)
        #expect(predicate!.contains("processImagePath ENDSWITH \"/MyApp\""))
        #expect(predicate!.contains("processID == 42"))
        #expect(predicate!.contains("subsystem == \"com.my.app\""))
        #expect(predicate!.contains("category == \"net\""))
        #expect(predicate!.contains("messageType >= 16"))
    }

    @Test("buildPredicate with no parameters returns nil")
    func buildPredicateEmpty() {
        let predicate = PredicateBuilder.buildPredicate()

        #expect(predicate == nil)
    }

    @Test("buildPredicate with single parameter")
    func buildPredicateSingle() {
        let predicate = PredicateBuilder.buildPredicate(subsystem: "com.apple.network")

        #expect(predicate == "subsystem == \"com.apple.network\"")
        #expect(predicate?.contains(" AND ") == false)
    }
}
