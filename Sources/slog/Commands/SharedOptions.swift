//
//  SharedOptions.swift
//  slog
//

import ArgumentParser

/// Filter options shared by `stream`, `show` and `profile create`.
struct FilterOptions: ParsableArguments {
    @Option(name: .long, help: "Filter by process name (comma-separated for multiple, e.g. Finder,Dock)")
    var process: String?

    @Option(name: .long, help: "Filter by process ID")
    var pid: Int?

    @Option(
        name: .long,
        help: "Filter by subsystem (comma-separated for multiple, e.g. com.apple.network,com.apple.CFNetwork)"
    )
    var subsystem: String?

    @Option(name: .long, help: "Filter by category (comma-separated for multiple, e.g. http,dns)")
    var category: String?

    @Option(name: .long, help: "Minimum log level (debug, info, default, error, fault)")
    var level: LogLevel?

    @Option(name: .long, help: "Filter messages by regex pattern")
    var grep: String?

    @Option(name: .long, help: "Exclude messages matching regex pattern")
    var excludeGrep: String?
}

/// Output options shared by `stream`, `show` and `profile create`.
struct OutputOptions: ParsableArguments {
    @Option(name: .long, help: "Output format (plain, compact, color, json, toon)")
    var format: OutputFormat?

    @Option(name: .long, help: "Timestamp mode (absolute, relative)")
    var time: TimeMode?

    @Flag(name: .long, inversion: .prefixedNo, help: "Include info-level messages")
    var info: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Include debug-level messages")
    var debug: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Include source location info")
    var source: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Collapse consecutive identical messages")
    var dedup: Bool?
}

/// Command-line options merged with an optional profile: a value given on the
/// command line wins, the profile fills the gaps, then the defaults apply.
struct ResolvedOptions {
    let profile: Profile?

    let process: String?
    let pid: Int?
    let subsystem: String?
    let category: String?
    let level: LogLevel?
    let grep: String?
    let excludeGrep: String?

    let format: OutputFormat
    let time: TimeMode
    let info: Bool
    let debug: Bool
    let source: Bool
    let dedup: Bool

    init(filter: FilterOptions, output: OutputOptions, profile: Profile?) {
        self.profile = profile
        self.process = filter.process ?? profile?.process
        self.pid = filter.pid ?? profile?.pid
        self.subsystem = filter.subsystem ?? profile?.subsystem
        self.category = filter.category ?? profile?.category
        self.level = filter.level ?? profile?.resolvedLevel
        self.grep = filter.grep ?? profile?.grep
        self.excludeGrep = filter.excludeGrep ?? profile?.excludeGrep
        self.format = output.format ?? profile?.resolvedFormat ?? .color
        self.time = output.time ?? profile?.resolvedTimeMode ?? .absolute
        self.info = output.info ?? profile?.info ?? false
        self.debug = output.debug ?? profile?.debug ?? false
        self.source = output.source ?? profile?.source ?? false
        self.dedup = output.dedup ?? profile?.dedup ?? false
    }

    /// Loads `profileName` (if any) and merges it under the command-line options.
    init(filter: FilterOptions, output: OutputOptions, profileName: String?) throws {
        try self.init(filter: filter, output: output, profile: profileName.map { try ProfileManager.load($0) })
    }

    /// Server-side predicate, client-side filter chain and level inclusion for these options.
    func filterSetup(signpost: Bool) throws -> FilterSetup {
        try FilterSetup.build(
            processes: FilterSetup.splitCSV(process),
            pid: pid,
            subsystems: FilterSetup.splitCSV(subsystem),
            categories: FilterSetup.splitCSV(category),
            level: level,
            grep: grep,
            excludeGrep: excludeGrep,
            info: info,
            debug: debug,
            signpost: signpost
        )
    }

    func formatter() -> any LogFormatter {
        FormatterRegistry.formatter(for: format, highlightPattern: grep, timeMode: time)
    }
}
