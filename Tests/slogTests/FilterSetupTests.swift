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

    @Test
    func emptyFilterChain() throws {
        let setup = try FilterSetup.build(processes: ["Finder"])

        #expect(setup.filterChain.isEmpty == true)
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
