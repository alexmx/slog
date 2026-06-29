//
//  FilterSetupTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("FilterSetup Tests")
struct FilterSetupTests {
    // MARK: - Auto-Debug Logic

    @Test
    func autoDebugWithSubsystem() throws {
        let setup = try FilterSetup.build(subsystems: ["com.apple.network"])

        #expect(setup.includeDebug == true)
        #expect(setup.includeInfo == true)
    }

    @Test
    func noAutoDebugWithLevel() throws {
        let setup = try FilterSetup.build(
            subsystems: ["com.apple.network"],
            level: .error
        )

        #expect(setup.includeDebug == false)
        #expect(setup.includeInfo == false)
    }

    // MARK: - Level-Driven Inclusion

    //
    // `--level` is a minimum severity; asking for a debug/info floor must also
    // make the `log` subprocess emit those levels, or the query captures nothing.

    @Test("level: .debug captures debug (and info), even without a subsystem")
    func levelDebugEnablesDebug() throws {
        let withSubsystem = try FilterSetup.build(subsystems: ["com.apple.network"], level: .debug)
        #expect(withSubsystem.includeDebug == true)
        #expect(withSubsystem.includeInfo == true)

        // The original footgun: process-only + level debug used to capture nothing.
        let processOnly = try FilterSetup.build(processes: ["Finder"], level: .debug)
        #expect(processOnly.includeDebug == true)
        #expect(processOnly.includeInfo == true)

        // And with no filters at all.
        let bare = try FilterSetup.build(level: .debug)
        #expect(bare.includeDebug == true)
        #expect(bare.includeInfo == true)
    }

    @Test("level: .info captures info but not debug")
    func levelInfoEnablesInfoOnly() throws {
        let setup = try FilterSetup.build(processes: ["Finder"], level: .info)
        #expect(setup.includeInfo == true)
        #expect(setup.includeDebug == false)
    }

    @Test("level: .default/.error/.fault need neither info nor debug emission")
    func levelDefaultAndAboveNoInfoDebug() throws {
        for level in [LogLevel.default, .error, .fault] {
            let setup = try FilterSetup.build(processes: ["Finder"], level: level)
            #expect(setup.includeDebug == false)
            #expect(setup.includeInfo == false)
        }
    }

    @Test
    func noAutoDebugWithInfoFlag() throws {
        let setup = try FilterSetup.build(
            subsystems: ["com.apple.network"],
            info: true
        )

        #expect(setup.includeDebug == false)
        #expect(setup.includeInfo == true)
    }

    @Test
    func noAutoDebugWithDebugFlag() throws {
        let setup = try FilterSetup.build(
            subsystems: ["com.apple.network"],
            debug: true
        )

        #expect(setup.includeDebug == true)
        #expect(setup.includeInfo == true)
    }

    @Test
    func noAutoDebugWithoutSubsystem() throws {
        let setup = try FilterSetup.build(processes: ["Finder"])

        #expect(setup.includeDebug == false)
        #expect(setup.includeInfo == false)
    }

    @Test
    func defaultsNoInfoNoDebug() throws {
        let setup = try FilterSetup.build()

        #expect(setup.includeDebug == false)
        #expect(setup.includeInfo == false)
    }

    @Test
    func debugImpliesInfo() throws {
        let setup = try FilterSetup.build(debug: true)

        #expect(setup.includeDebug == true)
        #expect(setup.includeInfo == true)
    }

    @Test
    func infoAloneNoDebug() throws {
        let setup = try FilterSetup.build(info: true)

        #expect(setup.includeInfo == true)
        #expect(setup.includeDebug == false)
    }

    // MARK: - Predicate Building

    @Test
    func noFiltersPredicate() throws {
        let setup = try FilterSetup.build()

        #expect(setup.predicate == nil)
    }

    @Test
    func processFilter() throws {
        let setup = try FilterSetup.build(processes: ["Finder"])

        #expect(setup.predicate?.contains("processImagePath ENDSWITH \"/Finder\"") == true)
    }

    @Test
    func subsystemAndCategory() throws {
        let setup = try FilterSetup.build(
            subsystems: ["com.apple.network"],
            categories: ["http"]
        )

        #expect(setup.predicate?.contains("subsystem BEGINSWITH \"com.apple.network\"") == true)
        #expect(setup.predicate?.contains("category == \"http\"") == true)
        #expect(setup.predicate?.contains(" AND ") == true)
    }

    @Test
    func pidFilter() throws {
        let setup = try FilterSetup.build(pid: 1234)

        #expect(setup.predicate?.contains("processID == 1234") == true)
    }

    @Test
    func multipleProcesses() throws {
        let setup = try FilterSetup.build(processes: ["Finder", "Dock"])

        #expect(setup.predicate == "(processImagePath ENDSWITH \"/Finder\" OR processImagePath ENDSWITH \"/Dock\")")
    }

    @Test
    func multipleSubsystems() throws {
        let setup = try FilterSetup.build(subsystems: ["com.apple.network", "com.apple.CFNetwork"])

        #expect(setup
            .predicate ==
            "(subsystem BEGINSWITH \"com.apple.network\" OR subsystem BEGINSWITH \"com.apple.CFNetwork\")")
    }

    @Test
    func multipleCategories() throws {
        let setup = try FilterSetup.build(categories: ["http", "dns"])

        #expect(setup.predicate == "(category == \"http\" OR category == \"dns\")")
    }

    @Test
    func autoDebugMultipleSubsystems() throws {
        let setup = try FilterSetup.build(subsystems: ["com.apple.network", "com.apple.CFNetwork"])

        #expect(setup.includeDebug == true)
        #expect(setup.includeInfo == true)
    }

    // MARK: - splitCSV Helper

    @Test
    func splitCSVNil() {
        #expect(FilterSetup.splitCSV(nil) == [])
    }

    @Test
    func splitCSVBasic() {
        #expect(FilterSetup.splitCSV("a,b,c") == ["a", "b", "c"])
    }

    @Test
    func splitCSVTrims() {
        #expect(FilterSetup.splitCSV(" a , b ,  c ") == ["a", "b", "c"])
    }

    @Test
    func splitCSVDropsEmpty() {
        #expect(FilterSetup.splitCSV("a,,b,") == ["a", "b"])
    }

    @Test
    func splitCSVSingle() {
        #expect(FilterSetup.splitCSV("just-one") == ["just-one"])
    }

    // MARK: - Filter Chain

    @Test("Filter chain stays empty only when no filter args are given")
    func emptyFilterChainWithNoArgs() throws {
        let setup = try FilterSetup.build()
        #expect(setup.filterChain.isEmpty == true)
    }

    @Test("Field filters populate the chain too — needed so source_file replay enforces them")
    func fieldFiltersPopulateChain() throws {
        let processOnly = try FilterSetup.build(processes: ["Finder"])
        #expect(processOnly.filterChain.isEmpty == false)

        let multi = try FilterSetup.build(
            processes: ["Finder", "Dock"],
            pid: 42,
            subsystems: ["com.apple.network"],
            categories: ["http"],
            level: .error
        )
        // One predicate per non-empty field (processes/subsystems/categories
        // each become a single AnyOfPredicate regardless of value count).
        #expect(multi.filterChain.count == 5)
    }

    @Test("Field filters in the chain match entries — drives source_file drill-down correctness")
    func fieldFiltersMatchEntries() throws {
        let setup = try FilterSetup.build(
            processes: ["Finder", "Dock"],
            level: .error
        )

        let matching = LogEntry(
            timestamp: Date(), processName: "Finder", pid: 1,
            subsystem: nil, category: nil, level: .error,
            message: "boom"
        )
        let wrongProcess = LogEntry(
            timestamp: Date(), processName: "Other", pid: 1,
            subsystem: nil, category: nil, level: .error,
            message: "boom"
        )
        let wrongLevel = LogEntry(
            timestamp: Date(), processName: "Finder", pid: 1,
            subsystem: nil, category: nil, level: .default,
            message: "ok"
        )

        #expect(setup.filterChain.matches(matching) == true)
        #expect(setup.filterChain.matches(wrongProcess) == false)
        #expect(setup.filterChain.matches(wrongLevel) == false)
    }

    @Test
    func grepFilterChain() throws {
        let setup = try FilterSetup.build(grep: "error")

        #expect(setup.filterChain.isEmpty == false)
        #expect(setup.filterChain.count == 1)
    }

    @Test
    func excludeGrepFilterChain() throws {
        let setup = try FilterSetup.build(excludeGrep: "heartbeat")

        #expect(setup.filterChain.isEmpty == false)
        #expect(setup.filterChain.count == 1)
    }

    @Test
    func bothGrepPatterns() throws {
        let setup = try FilterSetup.build(grep: "error", excludeGrep: "heartbeat")

        #expect(setup.filterChain.count == 2)
    }

    @Test
    func grepFilterMatches() throws {
        let setup = try FilterSetup.build(grep: "error")

        let matching = LogEntry(
            timestamp: Date(), processName: "Test", pid: 1,
            subsystem: nil, category: nil, level: .default,
            message: "An error occurred"
        )
        let nonMatching = LogEntry(
            timestamp: Date(), processName: "Test", pid: 1,
            subsystem: nil, category: nil, level: .default,
            message: "All good"
        )

        #expect(setup.filterChain.matches(matching) == true)
        #expect(setup.filterChain.matches(nonMatching) == false)
    }

    @Test
    func excludeGrepFilterMatches() throws {
        let setup = try FilterSetup.build(excludeGrep: "heartbeat")

        let excluded = LogEntry(
            timestamp: Date(), processName: "Test", pid: 1,
            subsystem: nil, category: nil, level: .default,
            message: "heartbeat: system healthy"
        )
        let kept = LogEntry(
            timestamp: Date(), processName: "Test", pid: 1,
            subsystem: nil, category: nil, level: .default,
            message: "User logged in"
        )

        #expect(setup.filterChain.matches(excluded) == false)
        #expect(setup.filterChain.matches(kept) == true)
    }
}
