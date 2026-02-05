//
//  ShowConfigurationTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("ShowConfiguration Tests")
struct ShowConfigurationTests {
    @Test("Default configuration has expected values")
    func defaultConfiguration() {
        let config = ShowConfiguration()

        #expect(config.timeRange == nil)
        #expect(config.archivePath == nil)
        #expect(config.predicate == nil)
        #expect(config.includeInfo == true)
        #expect(config.includeDebug == false)
    }

    @Test("Configuration with last duration")
    func lastDuration() {
        let config = ShowConfiguration(timeRange: .last("5m"))

        if case .last(let duration) = config.timeRange {
            #expect(duration == "5m")
        } else {
            Issue.record("Expected .last time range")
        }
    }

    @Test("Configuration with last boot")
    func lastBoot() {
        let config = ShowConfiguration(timeRange: .lastBoot)

        if case .lastBoot = config.timeRange {
            // OK
        } else {
            Issue.record("Expected .lastBoot time range")
        }
    }

    @Test("Configuration with date range")
    func dateRange() {
        let config = ShowConfiguration(
            timeRange: .range(start: "2024-01-15 10:00:00", end: "2024-01-15 11:00:00")
        )

        if case .range(let start, let end) = config.timeRange {
            #expect(start == "2024-01-15 10:00:00")
            #expect(end == "2024-01-15 11:00:00")
        } else {
            Issue.record("Expected .range time range")
        }
    }

    @Test("Configuration with archive path")
    func archivePath() {
        let config = ShowConfiguration(archivePath: "/tmp/test.logarchive")

        #expect(config.archivePath == "/tmp/test.logarchive")
    }
}

@Suite("LogReader Command Building Tests")
struct LogReaderCommandTests {
    let reader = LogReader()

    @Test("Basic arguments include show and ndjson style")
    func basicArguments() {
        let config = ShowConfiguration()
        let args = reader.buildArguments(for: config)

        #expect(args[0] == "show")
        #expect(args[1] == "--style")
        #expect(args[2] == "ndjson")
    }

    @Test("Info flag is included by default")
    func infoFlag() {
        let config = ShowConfiguration(includeInfo: true)
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--info"))
    }

    @Test("Debug flag included when set")
    func debugFlag() {
        let config = ShowConfiguration(includeDebug: true)
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--debug"))
    }

    @Test("Last duration argument")
    func lastDurationArg() {
        let config = ShowConfiguration(timeRange: .last("5m"))
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--last"))
        if let idx = args.firstIndex(of: "--last") {
            #expect(args[idx + 1] == "5m")
        }
    }

    @Test("Last boot argument")
    func lastBootArg() {
        let config = ShowConfiguration(timeRange: .lastBoot)
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--last"))
        if let idx = args.firstIndex(of: "--last") {
            #expect(args[idx + 1] == "boot")
        }
    }

    @Test("Start and end date arguments")
    func startEndArgs() {
        let config = ShowConfiguration(
            timeRange: .range(start: "2024-01-15 10:00:00", end: "2024-01-15 11:00:00")
        )
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--start"))
        #expect(args.contains("--end"))
        if let idx = args.firstIndex(of: "--start") {
            #expect(args[idx + 1] == "2024-01-15 10:00:00")
        }
        if let idx = args.firstIndex(of: "--end") {
            #expect(args[idx + 1] == "2024-01-15 11:00:00")
        }
    }

    @Test("Predicate argument")
    func predicateArg() {
        let config = ShowConfiguration(predicate: "processImagePath ENDSWITH \"/Finder\"")
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--predicate"))
        if let idx = args.firstIndex(of: "--predicate") {
            #expect(args[idx + 1] == "processImagePath ENDSWITH \"/Finder\"")
        }
    }

    @Test("Archive path is last argument")
    func archivePathArg() {
        let config = ShowConfiguration(
            timeRange: .last("1m"),
            archivePath: "/tmp/test.logarchive"
        )
        let args = reader.buildArguments(for: config)

        #expect(args.last == "/tmp/test.logarchive")
    }

    @Test("No info or debug flags when disabled")
    func noInfoDebugFlags() {
        let config = ShowConfiguration(includeInfo: false, includeDebug: false)
        let args = reader.buildArguments(for: config)

        #expect(!args.contains("--info"))
        #expect(!args.contains("--debug"))
    }
}
