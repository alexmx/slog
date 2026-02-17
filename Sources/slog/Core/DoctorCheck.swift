//
//  DoctorCheck.swift
//  slog
//

import Foundation

/// Result of a single system health check
public struct DoctorCheck: Codable, Sendable {
    public let name: String
    public let status: String // "ok", "fail", "info"
    public let hint: String?

    public init(name: String, status: String, hint: String? = nil) {
        self.name = name
        self.status = status
        self.hint = hint
    }

    /// Run all system health checks
    public static func runAll() -> [DoctorCheck] {
        var checks: [DoctorCheck] = []

        let logExists = FileManager.default.isExecutableFile(atPath: "/usr/bin/log")
        checks.append(DoctorCheck(
            name: "log CLI (/usr/bin/log)",
            status: logExists ? "ok" : "fail",
            hint: logExists ? nil : "The macOS unified logging CLI is missing. It should be included with macOS."
        ))

        let streamOK = checkCommand("/usr/bin/log", arguments: ["stream", "--timeout", "1"])
        checks.append(DoctorCheck(
            name: "Log stream access",
            status: streamOK ? "ok" : "fail",
            hint: streamOK ? nil : "Unable to stream logs. Grant Full Disk Access to your terminal app:\n  System Settings > Privacy & Security > Full Disk Access"
        ))

        let showOK = checkCommand("/usr/bin/log", arguments: ["show", "--last", "1s", "--style", "ndjson"])
        checks.append(DoctorCheck(
            name: "Log archive access (log show)",
            status: showOK ? "ok" : "fail",
            hint: showOK ? nil : "Unable to query log archives. Grant Full Disk Access to your terminal app:\n  System Settings > Privacy & Security > Full Disk Access"
        ))

        let simctlExists = FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun")
        let simctlOK = simctlExists && checkCommand("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"])
        checks.append(DoctorCheck(
            name: "Simulator support (xcrun simctl)",
            status: simctlOK ? "ok" : "fail",
            hint: simctlOK ? nil : "Install Xcode Command Line Tools: xcode-select --install"
        ))

        let profilesURL = XDGDirectories.profilesDirectory
        let profilesExist = FileManager.default.fileExists(atPath: profilesURL.path)
        checks.append(DoctorCheck(
            name: "Profiles directory (\(profilesURL.path))",
            status: profilesExist ? "ok" : "info",
            hint: profilesExist ? nil : "Will be created automatically when you save your first profile."
        ))

        return checks
    }

    private static func checkCommand(_ path: String, arguments: [String]) -> Bool {
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
