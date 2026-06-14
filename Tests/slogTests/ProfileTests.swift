//
//  ProfileTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("XDGDirectories Tests")
struct XDGDirectoriesTests {
    @Test
    func fallbackToDefault() {
        // When XDG_CONFIG_HOME is not set to an absolute path, should use ~/.config
        let configHome = XDGDirectories.configHome
        // Verify it returns a valid absolute path
        #expect(configHome.path.hasPrefix("/"))
    }

    @Test
    func profilesDirectory() {
        let dir = XDGDirectories.profilesDirectory
        #expect(dir.path.hasSuffix("slog/profiles"))
    }

    @Test
    func slogConfig() {
        let dir = XDGDirectories.slogConfig
        #expect(dir.path.hasSuffix("slog"))
    }
}

@Suite("Profile Tests")
struct ProfileTests {
    @Test
    func roundTrip() throws {
        let profile = Profile(
            process: "MyApp",
            subsystem: "com.myapp.network",
            level: "debug",
            format: "compact",
            info: true,
            source: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)

        #expect(decoded == profile)
    }

    @Test
    func partialFields() throws {
        let json = """
        {"process": "Finder", "level": "error"}
        """
        let data = try #require(json.data(using: .utf8))
        let profile = try JSONDecoder().decode(Profile.self, from: data)

        #expect(profile.process == "Finder")
        #expect(profile.level == "error")
        #expect(profile.subsystem == nil)
        #expect(profile.format == nil)
        #expect(profile.info == nil)
        #expect(profile.debug == nil)
    }

    @Test
    func emptyProfile() {
        let profile = Profile()
        #expect(profile.isEmpty)
    }

    @Test
    func nonEmptyProfile() {
        let profile = Profile(process: "Test")
        #expect(!profile.isEmpty)
    }

    @Test
    func resolvedLevel() {
        let profile = Profile(level: "error")
        #expect(profile.resolvedLevel == .error)
    }

    @Test
    func resolvedLevelInvalid() {
        let profile = Profile(level: "invalid")
        #expect(profile.resolvedLevel == nil)
    }

    @Test
    func resolvedFormat() {
        let profile = Profile(format: "json")
        #expect(profile.resolvedFormat == .json)
    }

    @Test
    func resolvedFormatInvalid() {
        let profile = Profile(format: "invalid")
        #expect(profile.resolvedFormat == nil)
    }

    @Test
    func resolvedTimeMode() {
        let profile = Profile(time: "relative")
        #expect(profile.resolvedTimeMode == .relative)
    }

    @Test
    func resolvedTimeModeInvalid() {
        let profile = Profile(time: "invalid")
        #expect(profile.resolvedTimeMode == nil)
    }

    @Test
    func nilFieldsOmitted() throws {
        let profile = Profile(process: "MyApp")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(profile)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"process\""))
        #expect(!json.contains("\"subsystem\""))
        #expect(!json.contains("\"level\""))
        #expect(!json.contains("\"format\""))
    }
}

@Suite("ProfileManager Tests")
struct ProfileManagerTests {
    /// Create a temporary directory for test profiles
    private func withTempProfileDir(_ body: (URL) throws -> Void) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slog-test-\(UUID().uuidString)")
            .appendingPathComponent("profiles")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent())
        }
        try body(tempDir)
    }

    @Test
    func saveAndLoad() throws {
        try withTempProfileDir { dir in
            let profile = Profile(process: "TestApp", level: "info", format: "json")

            let url = dir.appendingPathComponent("test.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profile)
            try data.write(to: url)

            let loadedData = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode(Profile.self, from: loadedData)

            #expect(loaded.process == "TestApp")
            #expect(loaded.level == "info")
            #expect(loaded.format == "json")
        }
    }

    @Test
    func listProfiles() throws {
        try withTempProfileDir { dir in
            let profile = Profile(process: "Test")
            let encoder = JSONEncoder()
            let data = try encoder.encode(profile)

            try data.write(to: dir.appendingPathComponent("beta.json"))
            try data.write(to: dir.appendingPathComponent("alpha.json"))
            try data.write(to: dir.appendingPathComponent("gamma.json"))

            let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            let names = contents
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
                .sorted()

            #expect(names == ["alpha", "beta", "gamma"])
        }
    }

    @Test
    func deleteProfile() throws {
        try withTempProfileDir { dir in
            let url = dir.appendingPathComponent("todelete.json")
            let data = try JSONEncoder().encode(Profile(process: "Test"))
            try data.write(to: url)

            #expect(FileManager.default.fileExists(atPath: url.path))

            try FileManager.default.removeItem(at: url)

            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test
    func errorDescriptions() {
        let notFound = ProfileError.notFound("test")
        #expect(notFound.errorDescription?.contains("test") == true)

        let invalid = ProfileError.invalidProfile("bad json")
        #expect(invalid.errorDescription?.contains("bad json") == true)

        let exists = ProfileError.alreadyExists("myprofile")
        #expect(exists.errorDescription?.contains("myprofile") == true)
        #expect(exists.errorDescription?.contains("--force") == true)
    }
}
