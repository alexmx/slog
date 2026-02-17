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

        var allPassed = true

        // 1. Check /usr/bin/log
        let logExists = FileManager.default.isExecutableFile(atPath: "/usr/bin/log")
        printCheck(logExists, "log CLI (/usr/bin/log)")
        if !logExists {
            printHint("The macOS unified logging CLI is missing. It should be included with macOS.")
            allPassed = false
        }

        // 2. Check log stream access
        let streamOK = checkCommand("/usr/bin/log", arguments: ["stream", "--timeout", "1"])
        printCheck(streamOK, "Log stream access")
        if !streamOK {
            printHint("Unable to stream logs. Grant Full Disk Access to your terminal app:")
            printHint("  System Settings > Privacy & Security > Full Disk Access")
            allPassed = false
        }

        // 3. Check log show access
        let showOK = checkCommand("/usr/bin/log", arguments: ["show", "--last", "1s", "--style", "ndjson"])
        printCheck(showOK, "Log archive access (log show)")
        if !showOK {
            printHint("Unable to query log archives. Grant Full Disk Access to your terminal app:")
            printHint("  System Settings > Privacy & Security > Full Disk Access")
            allPassed = false
        }

        // 4. Check xcrun simctl
        let simctlExists = FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun")
        let simctlOK = simctlExists && checkCommand("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"])
        printCheck(simctlOK, "Simulator support (xcrun simctl)")
        if !simctlOK {
            printHint("Install Xcode Command Line Tools: xcode-select --install")
            allPassed = false
        }

        // 5. Check profiles directory
        let profilesURL = XDGDirectories.profilesDirectory
        let profilesExist = FileManager.default.fileExists(atPath: profilesURL.path)
        printCheck(profilesExist ? .ok : .info, "Profiles directory (\(profilesURL.path))")
        if !profilesExist {
            printHint("Will be created automatically when you save your first profile.")
        }

        // Summary
        print("")
        if allPassed {
            print("All checks passed. slog is ready to use.")
        } else {
            print("Some checks failed. See hints above.")
        }
    }

    // MARK: - Helpers

    private enum CheckResult: String {
        case ok = "OK"
        case info = "INFO"
        case fail = "FAIL"
    }

    private func printCheck(_ result: CheckResult, _ label: String) {
        print("  [\(result.rawValue)] \(label)")
    }

    private func printCheck(_ passed: Bool, _ label: String) {
        printCheck(passed ? .ok : .fail, label)
    }

    private func printHint(_ message: String) {
        print("        \(message)")
    }

    private func checkCommand(_ path: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
