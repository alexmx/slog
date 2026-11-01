//
//  LogTargetTests.swift
//  slog
//

import ArgumentParser
@testable import slog
import Testing

@Suite("LogTarget Tests")
struct LogTargetTests {
    @Test
    func localRunsLogDirectly() {
        let (executable, args) = LogTarget.local.command(["show", "--last", "1m"])
        #expect("\(executable)".contains("/usr/bin/log"))
        #expect(args == ["show", "--last", "1m"])
    }

    @Test
    func simulatorRunsLogThroughSimctl() {
        let (executable, args) = LogTarget.simulator(udid: "U").command(["show"])
        #expect("\(executable)".contains("xcrun"))
        #expect(args == ["simctl", "spawn", "U", "log", "show"])
    }

    @Test
    func showOnSimulatorKeepsTimeRangeAndPredicate() {
        let config = ShowConfiguration(target: .simulator(udid: "U"), timeRange: .last("5m"), predicate: "pid == 1")
        let (_, args) = LogReader().buildCommand(for: config)
        #expect(Array(args.prefix(5)) == ["simctl", "spawn", "U", "log", "show"])
        #expect(args.contains("--last") && args.contains("5m"))
        #expect(args.last == "pid == 1")
    }

    @Test
    func resolveDefaultsToLocal() async throws {
        #expect(try await LogTarget.Request().resolve() == .local)
        #expect(!LogTarget.Request().isRequested)
    }

    @Test
    func udidImpliesSimulatorWithoutLookup() async throws {
        #expect(LogTarget.Request(udid: "ABC").isRequested)
        #expect(try await LogTarget.Request(udid: "ABC").resolve() == .simulator(udid: "ABC"))
        #expect(try await LogTarget.Request(simulator: true, udid: "ABC").resolve() == .simulator(udid: "ABC"))
    }

    @Test
    func showRejectsSimulatorWithArchive() async throws {
        let command = try ShowCommand.parse(["--simulator", "/tmp/some.logarchive"])
        await #expect(throws: ValidationError.self) {
            try await command.run()
        }
    }
}
