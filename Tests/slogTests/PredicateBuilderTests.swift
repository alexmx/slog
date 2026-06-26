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

    @Test
    func processFilter() {
        var builder = PredicateBuilder()
        builder.processes(["Finder"])
        let predicate = builder.build()

        #expect(predicate == "processImagePath ENDSWITH \"/Finder\"")
    }

    @Test
    func multipleProcesses() {
        var builder = PredicateBuilder()
        builder.processes(["Finder", "Dock"])
        let predicate = builder.build()

        #expect(predicate == "(processImagePath ENDSWITH \"/Finder\" OR processImagePath ENDSWITH \"/Dock\")")
    }

    @Test
    func emptyProcesses() {
        var builder = PredicateBuilder()
        builder.processes([])
        builder.pid(42)
        let predicate = builder.build()

        #expect(predicate == "processID == 42")
    }

    @Test
    func pidFilter() {
        var builder = PredicateBuilder()
        builder.pid(1234)
        let predicate = builder.build()

        #expect(predicate == "processID == 1234")
    }

    @Test
    func subsystemFilter() {
        var builder = PredicateBuilder()
        builder.subsystems(["com.apple.network"])
        let predicate = builder.build()

        #expect(predicate == "subsystem BEGINSWITH \"com.apple.network\"")
    }

    @Test
    func multipleSubsystems() {
        var builder = PredicateBuilder()
        builder.subsystems(["com.apple.network", "com.apple.CFNetwork"])
        let predicate = builder.build()

        #expect(predicate ==
            "(subsystem BEGINSWITH \"com.apple.network\" OR subsystem BEGINSWITH \"com.apple.CFNetwork\")")
    }

    @Test
    func categoryFilter() {
        var builder = PredicateBuilder()
        builder.categories(["http"])
        let predicate = builder.build()

        #expect(predicate == "category == \"http\"")
    }

    @Test
    func multipleCategories() {
        var builder = PredicateBuilder()
        builder.categories(["http", "dns"])
        let predicate = builder.build()

        #expect(predicate == "(category == \"http\" OR category == \"dns\")")
    }

    @Test(
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

    // MARK: - Combinations

    @Test
    func multiplePredicates() {
        var builder = PredicateBuilder()
        builder.processes(["MyApp"])
        builder.subsystems(["com.my.app"])
        let predicate = builder.build()

        #expect(predicate?.contains(" AND ") == true)
        #expect(predicate?.contains("processImagePath ENDSWITH \"/MyApp\"") == true)
        #expect(predicate?.contains("subsystem BEGINSWITH \"com.my.app\"") == true)
    }

    @Test
    func emptyBuilder() {
        let builder = PredicateBuilder()
        let predicate = builder.build()

        #expect(predicate == nil)
    }

    // MARK: - Static Helper

    @Test
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

    @Test
    func buildPredicateEmpty() {
        let predicate = PredicateBuilder.buildPredicate()

        #expect(predicate == nil)
    }

    @Test
    func buildPredicateSignpostOnly() throws {
        let predicate = PredicateBuilder.buildPredicate(
            subsystems: ["com.my.app"],
            categories: ["perf"],
            signpostOnly: true
        )

        #expect(try #require(predicate?.contains("eventType == \"signpostEvent\"")))
        #expect(try #require(predicate?.contains("subsystem BEGINSWITH \"com.my.app\"")))
        #expect(try #require(predicate?.contains("category == \"perf\"")))
    }

    @Test
    func signpostModeSkipsLevelConstraint() throws {
        // Level must be ignored in signpost mode — signpost events carry a
        // different messageType and would be filtered out by a level clause.
        let predicate = PredicateBuilder.buildPredicate(
            subsystems: ["com.my.app"],
            level: .error,
            signpostOnly: true
        )

        #expect(predicate?.contains("messageType") == false)
        #expect(try #require(predicate?.contains("eventType == \"signpostEvent\"")))
    }

    @Test
    func buildPredicateSingle() {
        let predicate = PredicateBuilder.buildPredicate(subsystems: ["com.apple.network"])

        #expect(predicate == "subsystem BEGINSWITH \"com.apple.network\"")
        #expect(predicate?.contains(" AND ") == false)
    }

    @Test
    func buildPredicateMultipleSubsystemsWithCategory() {
        let predicate = PredicateBuilder.buildPredicate(
            subsystems: ["com.apple.network", "com.apple.CFNetwork"],
            categories: ["http"]
        )

        let expected = "(subsystem BEGINSWITH \"com.apple.network\" OR subsystem BEGINSWITH \"com.apple.CFNetwork\") AND category == \"http\""
        #expect(predicate == expected)
    }
}
