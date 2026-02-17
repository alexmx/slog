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

    @Test("Auto-debug enables when subsystem set without level")
    func autoDebugWithSubsystem() {
        let setup = FilterSetup.build(subsystem: "com.apple.network")

        #expect(setup.includeDebug == true)
        #expect(setup.includeInfo == true)
    }

    @Test("Auto-debug disabled when level is explicit")
    func noAutoDebugWithLevel() {
        let setup = FilterSetup.build(
            subsystem: "com.apple.network",
            level: .error
        )

        #expect(setup.includeDebug == false)
        #expect(setup.includeInfo == false)
    }

    @Test("Auto-debug disabled when info flag is explicit")
    func noAutoDebugWithInfoFlag() {
        let setup = FilterSetup.build(
            subsystem: "com.apple.network",
            info: true
        )

        #expect(setup.includeDebug == false)
        #expect(setup.includeInfo == true)
    }

    @Test("Auto-debug disabled when debug flag is explicit")
    func noAutoDebugWithDebugFlag() {
        let setup = FilterSetup.build(
            subsystem: "com.apple.network",
            debug: true
        )

        #expect(setup.includeDebug == true)
        #expect(setup.includeInfo == true)
    }

    @Test("No auto-debug without subsystem")
    func noAutoDebugWithoutSubsystem() {
        let setup = FilterSetup.build(process: "Finder")

        #expect(setup.includeDebug == false)
        #expect(setup.includeInfo == false)
    }

    @Test("No flags defaults to no info or debug")
    func defaultsNoInfoNoDebug() {
        let setup = FilterSetup.build()

        #expect(setup.includeDebug == false)
        #expect(setup.includeInfo == false)
    }

    @Test("Debug flag implies info inclusion")
    func debugImpliesInfo() {
        let setup = FilterSetup.build(debug: true)

        #expect(setup.includeDebug == true)
        #expect(setup.includeInfo == true)
    }

    @Test("Info flag alone enables info but not debug")
    func infoAloneNoDebug() {
        let setup = FilterSetup.build(info: true)

        #expect(setup.includeInfo == true)
        #expect(setup.includeDebug == false)
    }

    // MARK: - Predicate Building

    @Test("Predicate is nil when no filters set")
    func noFiltersPredicate() {
        let setup = FilterSetup.build()

        #expect(setup.predicate == nil)
    }

    @Test("Predicate includes process filter")
    func processFilter() {
        let setup = FilterSetup.build(process: "Finder")

        #expect(setup.predicate?.contains("processImagePath ENDSWITH \"/Finder\"") == true)
    }

    @Test("Predicate includes subsystem and category")
    func subsystemAndCategory() {
        let setup = FilterSetup.build(
            subsystem: "com.apple.network",
            category: "http"
        )

        #expect(setup.predicate?.contains("subsystem == \"com.apple.network\"") == true)
        #expect(setup.predicate?.contains("category == \"http\"") == true)
        #expect(setup.predicate?.contains(" AND ") == true)
    }

    @Test("Predicate includes pid")
    func pidFilter() {
        let setup = FilterSetup.build(pid: 1234)

        #expect(setup.predicate?.contains("processID == 1234") == true)
    }

    // MARK: - Filter Chain

    @Test("Filter chain is empty when no grep patterns")
    func emptyFilterChain() {
        let setup = FilterSetup.build(process: "Finder")

        #expect(setup.filterChain.isEmpty == true)
    }

    @Test("Filter chain includes grep pattern")
    func grepFilterChain() {
        let setup = FilterSetup.build(grep: "error")

        #expect(setup.filterChain.isEmpty == false)
        #expect(setup.filterChain.count == 1)
    }

    @Test("Filter chain includes exclude-grep pattern")
    func excludeGrepFilterChain() {
        let setup = FilterSetup.build(excludeGrep: "heartbeat")

        #expect(setup.filterChain.isEmpty == false)
        #expect(setup.filterChain.count == 1)
    }

    @Test("Filter chain includes both grep and exclude-grep")
    func bothGrepPatterns() {
        let setup = FilterSetup.build(grep: "error", excludeGrep: "heartbeat")

        #expect(setup.filterChain.count == 2)
    }

    @Test("Grep filter chain matches correctly")
    func grepFilterMatches() {
        let setup = FilterSetup.build(grep: "error")

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

    @Test("Exclude-grep filter chain excludes correctly")
    func excludeGrepFilterMatches() {
        let setup = FilterSetup.build(excludeGrep: "heartbeat")

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
