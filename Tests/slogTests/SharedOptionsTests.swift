//
//  SharedOptionsTests.swift
//  slog
//

import ArgumentParser
@testable import slog
import Testing

@Suite("SharedOptions Tests")
struct SharedOptionsTests {
    /// Both groups as one parsable set, the way commands embed them.
    private struct Options: ParsableArguments {
        @OptionGroup var filter: FilterOptions
        @OptionGroup var output: OutputOptions
    }

    private func resolve(_ arguments: [String], profile: Profile? = nil) throws -> ResolvedOptions {
        let parsed = try Options.parse(arguments)
        return ResolvedOptions(filter: parsed.filter, output: parsed.output, profile: profile)
    }

    // MARK: - Merge rules

    @Test
    func defaultsApplyWithoutCLIOrProfile() throws {
        let options = try resolve([])
        #expect(options.format == .color)
        #expect(options.time == .absolute)
        #expect(!options.info && !options.debug && !options.source && !options.dedup)
        #expect(options.process == nil && options.level == nil)
    }

    @Test
    func profileFillsUnsetOptions() throws {
        let profile = Profile(process: "Finder", level: "error", format: "json", time: "relative", debug: true)
        let options = try resolve([], profile: profile)
        #expect(options.process == "Finder")
        #expect(options.level == .error)
        #expect(options.format == .json)
        #expect(options.time == .relative)
        #expect(options.debug)
    }

    @Test
    func commandLineWinsOverProfile() throws {
        let profile = Profile(process: "Finder", level: "error", format: "json", debug: true)
        let options = try resolve(
            ["--process", "Dock", "--level", "info", "--format", "plain", "--no-debug"],
            profile: profile
        )
        #expect(options.process == "Dock")
        #expect(options.level == .info)
        #expect(options.format == .plain)
        #expect(!options.debug)
    }

    @Test
    func filterSetupUsesMergedValues() throws {
        let options = try resolve(["--process", "Finder,Dock"], profile: Profile(subsystem: "com.app"))
        let setup = try options.filterSetup(signpost: false)
        #expect(setup.predicate?.contains("/Finder") == true)
        #expect(setup.predicate?.contains("/Dock") == true)
        #expect(setup.predicate?.contains("com.app") == true)
        // A bare subsystem filter auto-includes debug+info.
        #expect(setup.includeDebug)
    }

    // MARK: - profile create

    @Test
    func createProfileStoresOnlyGivenOptions() throws {
        let profile = try CreateProfile.parse(["p", "--process", "Finder", "--level", "Error", "--info"]).makeProfile()
        #expect(profile == Profile(process: "Finder", level: "error", info: true))
    }

    @Test
    func createProfileStoresExplicitFalse() throws {
        let profile = try CreateProfile.parse(["p", "--subsystem", "com.app", "--no-debug"]).makeProfile()
        #expect(profile.debug == false)
        #expect(profile.info == nil)
    }

    @Test
    func createProfileWithNoOptionsIsEmpty() throws {
        #expect(try CreateProfile.parse(["p"]).makeProfile().isEmpty)
    }
}
