//
//  DoctorCommand.swift
//  slog
//
//  Created by Alex Maimescu on 17/02/2026.
//

import ArgumentParser
import Foundation

/// Command for checking system requirements
struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check system requirements and diagnose issues"
    )

    func run() throws {
        print("slog doctor\n")

        let checks = DoctorCheck.runAll()
        var allPassed = true

        for check in checks {
            let label = switch check.status {
            case "ok": "OK"
            case "info": "INFO"
            default: "FAIL"
            }
            print("  [\(label)] \(check.name)")

            if let hint = check.hint {
                for line in hint.split(separator: "\n", omittingEmptySubsequences: false) {
                    print("        \(line)")
                }
            }

            if check.status == "fail" {
                allPassed = false
            }
        }

        print("")
        if allPassed {
            print("All checks passed. slog is ready to use.")
        } else {
            print("Some checks failed. See hints above.")
        }
    }
}
