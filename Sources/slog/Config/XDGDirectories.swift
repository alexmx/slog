//
//  XDGDirectories.swift
//  slog
//

import Foundation

/// XDG Base Directory Specification compliant path resolution.
/// Falls back to `~/.config` on macOS when `XDG_CONFIG_HOME` is unset.
enum XDGDirectories {
    /// User-specific configuration directory.
    /// Uses `$XDG_CONFIG_HOME` if set and absolute, otherwise `~/.config`.
    static var configHome: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
           xdg.hasPrefix("/") {
            return URL(fileURLWithPath: xdg)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
    }

    /// slog configuration directory (`$XDG_CONFIG_HOME/slog`).
    static var slogConfig: URL {
        configHome.appendingPathComponent("slog")
    }

    /// Profile storage directory (`$XDG_CONFIG_HOME/slog/profiles`).
    static var profilesDirectory: URL {
        slogConfig.appendingPathComponent("profiles")
    }

    /// User-specific cache directory.
    /// Uses `$XDG_CACHE_HOME` if set and absolute, otherwise `~/.cache`.
    static var cacheHome: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"],
           xdg.hasPrefix("/") {
            return URL(fileURLWithPath: xdg)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache")
    }

    /// slog cache directory (`$XDG_CACHE_HOME/slog`).
    static var slogCache: URL {
        cacheHome.appendingPathComponent("slog")
    }

    /// MCP run output directory (`$XDG_CACHE_HOME/slog/runs`).
    /// Used when a tool spills full results to disk and the caller didn't
    /// supply `output_file`.
    static var runsDirectory: URL {
        slogCache.appendingPathComponent("runs")
    }
}
