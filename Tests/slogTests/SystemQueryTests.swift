//
//  SystemQueryTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("SystemQuery Tests")
struct SystemQueryTests {
    // MARK: - Processes

    private let psOutput = """
      PID COMM
        1 /sbin/launchd
      402 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
      517 /usr/libexec/trustd
      518 /usr/libexec/trustd
      900 /Applications/Safari.app/Contents/MacOS/Safari
    garbage line
    """

    @Test
    func processesAreNamedByBinaryDedupedAndSorted() {
        let processes = SystemQuery.parseProcesses(psOutput, filter: nil)
        #expect(processes.map(\.name) == ["Finder", "launchd", "Safari", "trustd"])
        // First pid wins for duplicate names.
        #expect(processes.first { $0.name == "trustd" }?.pid == 517)
    }

    @Test
    func processFilterIsCaseInsensitiveSubstring() {
        let processes = SystemQuery.parseProcesses(psOutput, filter: "FIN")
        #expect(processes.map(\.name) == ["Finder"])
    }

    // MARK: - Simulators

    private let simctlJSON = Data("""
    {
      "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
          { "name": "iPhone 16", "udid": "A", "state": "Booted", "isAvailable": true },
          { "name": "iPhone 15", "udid": "B", "state": "Shutdown", "isAvailable": true },
          { "name": "Broken", "udid": "C", "state": "Shutdown", "isAvailable": false },
          { "udid": "D", "state": "Shutdown" }
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [
          { "name": "iPad", "udid": "E", "state": "Shutdown", "isAvailable": true }
        ]
      }
    }
    """.utf8)

    @Test
    func simulatorsSkipUnavailableAndIncompleteEntries() throws {
        let simulators = try SystemQuery.parseSimulators(simctlJSON, booted: false, all: false)
        #expect(simulators.map(\.udid) == ["E", "A", "B"])
        #expect(simulators.first?.runtime == "iOS 17 5")
    }

    @Test
    func allIncludesUnavailableSimulators() throws {
        let simulators = try SystemQuery.parseSimulators(simctlJSON, booted: false, all: true)
        #expect(simulators.map(\.udid) == ["E", "A", "B", "C"])
    }

    @Test
    func bootedKeepsOnlyBootedSimulators() throws {
        let simulators = try SystemQuery.parseSimulators(simctlJSON, booted: true, all: false)
        #expect(simulators.map(\.udid) == ["A"])
    }

    @Test
    func malformedSimctlOutputThrows() {
        #expect(throws: SystemQueryError.self) {
            try SystemQuery.parseSimulators(Data("not json".utf8), booted: false, all: false)
        }
    }

    // MARK: - Booted UDID

    private func simulator(_ udid: String, state: String) -> SimulatorInfo {
        SimulatorInfo(name: "Sim \(udid)", udid: udid, state: state, runtime: "iOS 18 2")
    }

    @Test
    func singleBootedSimulatorIsPicked() throws {
        let udid = try SystemQuery.bootedUDID(from: [
            simulator("A", state: "Shutdown"),
            simulator("B", state: "Booted")
        ])
        #expect(udid == "B")
    }

    @Test
    func noBootedSimulatorThrows() {
        #expect {
            try SystemQuery.bootedUDID(from: [simulator("A", state: "Shutdown")])
        } throws: { error in
            if case .noBootedSimulator = error as? SystemQueryError {
                true
            } else {
                false
            }
        }
    }

    @Test
    func multipleBootedSimulatorsThrowWithTheList() {
        #expect {
            try SystemQuery.bootedUDID(from: [simulator("A", state: "Booted"), simulator("B", state: "Booted")])
        } throws: { error in
            let message = (error as? SystemQueryError)?.errorDescription ?? ""
            return message.contains("Sim A (A)") && message.contains("Sim B (B)")
        }
    }
}
