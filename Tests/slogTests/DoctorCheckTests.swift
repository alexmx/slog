//
//  DoctorCheckTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("DoctorCheck Tests")
struct DoctorCheckTests {
    @Test
    func statusEncodesAsLowercaseStrings() throws {
        let checks = [
            DoctorCheck(name: "a", status: .ok),
            DoctorCheck(name: "b", status: .fail, hint: "fix it"),
            DoctorCheck(name: "c", status: .info)
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try String(decoding: encoder.encode(checks), as: UTF8.self)

        #expect(json ==
            #"[{"name":"a","status":"ok"},{"hint":"fix it","name":"b","status":"fail"},{"name":"c","status":"info"}]"#)
    }

    @Test
    func succeedsOnlyForAZeroExit() async {
        #expect(await DoctorCheck.succeeds("/bin/sh", ["-c", "exit 0"]))
        #expect(await !DoctorCheck.succeeds("/bin/sh", ["-c", "exit 1"]))
    }

    @Test
    func missingExecutableIsAFailure() async {
        #expect(await !DoctorCheck.succeeds("/nonexistent/tool", []))
    }
}
