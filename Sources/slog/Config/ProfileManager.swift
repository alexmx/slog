//
//  ProfileManager.swift
//  slog
//

import Foundation

/// Manages profile persistence in the XDG-compliant config directory
enum ProfileManager {
    /// Load a profile by name
    static func load(_ name: String) throws -> Profile {
        let url = profileURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProfileError.notFound(name)
        }

        let data = try Data(contentsOf: url)

        do {
            return try JSONDecoder().decode(Profile.self, from: data)
        } catch {
            throw ProfileError.invalidProfile("\(name): \(error.localizedDescription)")
        }
    }

    /// Save a profile by name (creates directories lazily)
    static func save(_ name: String, profile: Profile, force: Bool = false) throws {
        let url = profileURL(name)

        if !force && FileManager.default.fileExists(atPath: url.path) {
            throw ProfileError.alreadyExists(name)
        }

        // Create directories if needed
        let dir = XDGDirectories.profilesDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(to: url)
    }

    /// Delete a profile by name
    static func delete(_ name: String) throws {
        let url = profileURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProfileError.notFound(name)
        }
        try FileManager.default.removeItem(at: url)
    }

    /// List available profile names
    static func list() throws -> [String] {
        let dir = XDGDirectories.profilesDirectory

        guard FileManager.default.fileExists(atPath: dir.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )

        return contents
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// Check if a profile exists
    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: profileURL(name).path)
    }

    /// Get the file URL for a profile name
    static func profileURL(_ name: String) -> URL {
        XDGDirectories.profilesDirectory
            .appendingPathComponent(name)
            .appendingPathExtension("json")
    }
}

// MARK: - Errors

public enum ProfileError: Error, LocalizedError {
    case notFound(String)
    case invalidProfile(String)
    case alreadyExists(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "Profile not found: \(name)"
        case .invalidProfile(let message):
            return "Invalid profile: \(message)"
        case .alreadyExists(let name):
            return "Profile already exists: \(name). Use --force to overwrite."
        }
    }
}
