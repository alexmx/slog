//
//  DoctorCheck.swift
//  slog
//

import Foundation
import Subprocess
import System

/// Result of a single system health check
public struct DoctorCheck: Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case ok
        case fail
        /// Not a problem; the hint explains what will happen.
        case info
    }

    public let name: String
    public let status: Status
    public let hint: String?

    public init(name: String, status: Status, hint: String? = nil) {
        self.name = name
        self.status = status
        self.hint = hint
    }

    /// Run all system health checks
    public static func runAll() async -> [DoctorCheck] {
        // The command checks are independent, so run them concurrently.
        let simctlExists = FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun")
        async let streamCheck = succeeds("/usr/bin/log", ["stream", "--timeout", "1"])
        async let showCheck = succeeds("/usr/bin/log", ["show", "--last", "1s", "--style", "ndjson"])
        async let simctlCheck = simctlExists ? succeeds("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"]) : false

        var checks: [DoctorCheck] = []

        let logExists = FileManager.default.isExecutableFile(atPath: "/usr/bin/log")
        checks.append(DoctorCheck(
            name: "log CLI (/usr/bin/log)",
            status: logExists ? .ok : .fail,
            hint: logExists ? nil : "The macOS unified logging CLI is missing. It should be included with macOS."
        ))

        let streamOK = await streamCheck
        checks.append(DoctorCheck(
            name: "Log stream access",
            status: streamOK ? .ok : .fail,
            hint: streamOK ? nil : "Unable to stream logs. Grant Full Disk Access to your terminal app:\n  System Settings > Privacy & Security > Full Disk Access"
        ))

        let showOK = await showCheck
        checks.append(DoctorCheck(
            name: "Log archive access (log show)",
            status: showOK ? .ok : .fail,
            hint: showOK ? nil : "Unable to query log archives. Grant Full Disk Access to your terminal app:\n  System Settings > Privacy & Security > Full Disk Access"
        ))

        let simctlOK = await simctlCheck
        checks.append(DoctorCheck(
            name: "Simulator support (xcrun simctl)",
            status: simctlOK ? .ok : .fail,
            hint: simctlOK ? nil : "Install Xcode Command Line Tools: xcode-select --install"
        ))

        let profilesURL = XDGDirectories.profilesDirectory
        let profilesExist = FileManager.default.fileExists(atPath: profilesURL.path)
        checks.append(DoctorCheck(
            name: "Profiles directory (\(profilesURL.path))",
            status: profilesExist ? .ok : .info,
            hint: profilesExist ? nil : "Will be created automatically when you save your first profile."
        ))

        return checks
    }

    /// Whether the tool runs and exits 0, output discarded. Async (via
    /// swift-subprocess) so a check doesn't block a thread of Swift's shared
    /// async pool while it runs.
    static func succeeds(_ path: String, _ arguments: [String]) async -> Bool {
        do {
            let result = try await run(
                .path(FilePath(path)),
                arguments: Arguments(arguments),
                output: .discarded,
                error: .discarded
            )
            return result.terminationStatus.isSuccess
        } catch {
            return false
        }
    }
}
