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
        builder.processes(["Finder"])
        let predicate = builder.build()

        #expect(predicate == "processImagePath ENDSWITH \"/Finder\"")
    }

    @Test("Multiple processes OR-grouped")
    func multipleProcesses() {
        var builder = PredicateBuilder()
        builder.processes(["Finder", "Dock"])
        let predicate = builder.build()

        #expect(predicate == "(processImagePath ENDSWITH \"/Finder\" OR processImagePath ENDSWITH \"/Dock\")")
    }

    @Test("Empty processes array contributes no component")
    func emptyProcesses() {
        var builder = PredicateBuilder()
        builder.processes([])
        builder.pid(42)
        let predicate = builder.build()

        #expect(predicate == "processID == 42")
    }

    @Test("PID predicate uses equality")
    func pidFilter() {
        var builder = PredicateBuilder()
        builder.pid(1234)
        let predicate = builder.build()

        #expect(predicate == "processID == 1234")
    }

    @Test("Subsystem predicate uses BEGINSWITH")
    func subsystemFilter() {
        var builder = PredicateBuilder()
        builder.subsystems(["com.apple.network"])
        let predicate = builder.build()

        #expect(predicate == "subsystem BEGINSWITH \"com.apple.network\"")
    }

    @Test("Multiple subsystems OR-grouped")
    func multipleSubsystems() {
        var builder = PredicateBuilder()
        builder.subsystems(["com.apple.network", "com.apple.CFNetwork"])
        let predicate = builder.build()

        #expect(predicate == "(subsystem BEGINSWITH \"com.apple.network\" OR subsystem BEGINSWITH \"com.apple.CFNetwork\")")
    }

    @Test("Category predicate uses equality")
    func categoryFilter() {
        var builder = PredicateBuilder()
        builder.categories(["http"])
        let predicate = builder.build()

        #expect(predicate == "category == \"http\"")
    }

    @Test("Multiple categories OR-grouped")
    func multipleCategories() {
        var builder = PredicateBuilder()
        builder.categories(["http", "dns"])
        let predicate = builder.build()

        #expect(predicate == "(category == \"http\" OR category == \"dns\")")
    }

    @Test(
        "Level predicate uses messageType with correct values",
        arguments: [
            (LogLevel.debug, 0),
            (LogLevel.info, 1),
            (LogLevel.default, 2),
            (LogLevel.error, 16),
            (LogLevel.fault, 17),
        ]
    )
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
        builder.processes(["MyApp"])
        builder.subsystems(["com.my.app"])
        let predicate = builder.build()

        #expect(predicate?.contains(" AND ") == true)
        #expect(predicate?.contains("processImagePath ENDSWITH \"/MyApp\"") == true)
        #expect(predicate?.contains("subsystem BEGINSWITH \"com.my.app\"") == true)
    }

    @Test("Empty builder returns nil")
    func emptyBuilder() {
        let builder = PredicateBuilder()
        let predicate = builder.build()

        #expect(predicate == nil)
    }

    // MARK: - Static Helper

    @Test("buildPredicate with all parameters")
    func buildPredicateAllParams() throws {
        let predicate = PredicateBuilder.buildPredicate(
            processes: ["MyApp"],
            pid: 42,
            subsystems: ["com.my.app"],
            categories: ["net"],
            level: .error
        )

        #expect(predicate != nil)
        #expect(try #require(predicate?.contains("processImagePath ENDSWITH \"/MyApp\"")))
        #expect(try #require(predicate?.contains("processID == 42")))
        #expect(try #require(predicate?.contains("subsystem BEGINSWITH \"com.my.app\"")))
        #expect(try #require(predicate?.contains("category == \"net\"")))
        #expect(try #require(predicate?.contains("messageType >= 16")))
    }

    @Test("buildPredicate with no parameters returns nil")
    func buildPredicateEmpty() {
        let predicate = PredicateBuilder.buildPredicate()

        #expect(predicate == nil)
    }

    @Test("buildPredicate with single parameter")
    func buildPredicateSingle() {
        let predicate = PredicateBuilder.buildPredicate(subsystems: ["com.apple.network"])

        #expect(predicate == "subsystem BEGINSWITH \"com.apple.network\"")
        #expect(predicate?.contains(" AND ") == false)
    }

    @Test("buildPredicate OR-groups multiple subsystems and ANDs with category")
    func buildPredicateMultipleSubsystemsWithCategory() throws {
        let predicate = PredicateBuilder.buildPredicate(
            subsystems: ["com.apple.network", "com.apple.CFNetwork"],
            categories: ["http"]
        )

        let expected = "(subsystem BEGINSWITH \"com.apple.network\" OR subsystem BEGINSWITH \"com.apple.CFNetwork\") AND category == \"http\""
        #expect(predicate == expected)
    }
}
