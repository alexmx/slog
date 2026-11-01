//
//  DoctorCommand.swift
//  slog
//
//  Created by Alex Maimescu on 17/02/2026.
//

import ArgumentParser
import Foundation

/// Command for checking system requirements
struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check system requirements and diagnose issues"
    )

    func run() async throws {
        print("slog doctor\n")

        let checks = await DoctorCheck.runAll()

        for check in checks {
            let label = switch check.status {
            case .ok: "OK"
            case .info: "INFO"
            case .fail: "FAIL"
            }
            print("  [\(label)] \(check.name)")

            if let hint = check.hint {
                for line in hint.split(separator: "\n", omittingEmptySubsequences: false) {
                    print("        \(line)")
                }
            }
        }

        print("")
        if checks.allSatisfy({ $0.status != .fail }) {
            print("All checks passed. slog is ready to use.")
        } else {
            print("Some checks failed. See hints above.")
        }
    }
}
