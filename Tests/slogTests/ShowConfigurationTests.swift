//
//  ShowConfigurationTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("ShowConfiguration Tests")
struct ShowConfigurationTests {
    @Test
    func defaultConfiguration() {
        let config = ShowConfiguration()

        #expect(config.timeRange == nil)
        #expect(config.archivePath == nil)
        #expect(config.predicate == nil)
        #expect(config.includeInfo == true)
        #expect(config.includeDebug == false)
    }

    @Test
    func lastDuration() {
        let config = ShowConfiguration(timeRange: .last("5m"))

        if case .last(let duration) = config.timeRange {
            #expect(duration == "5m")
        } else {
            Issue.record("Expected .last time range")
        }
    }

    // MARK: - TimeRange(last:start:end:)

    @Test
    func timeRangeFromLast() {
        #expect(ShowConfiguration.TimeRange(last: "5m", start: nil, end: nil) == .last("5m"))
    }

    @Test
    func timeRangeNormalizesBootCase() {
        #expect(ShowConfiguration.TimeRange(last: "Boot", start: nil, end: nil) == .last("boot"))
        #expect(ShowConfiguration.TimeRange(last: "BOOT", start: nil, end: nil) == .last("boot"))
    }

    @Test
    func timeRangeFromStartOnly() {
        #expect(ShowConfiguration.TimeRange(last: nil, start: "2024-01-15", end: nil) == .start(.raw("2024-01-15")))
    }

    @Test
    func timeRangeFromStartAndEnd() {
        #expect(
            ShowConfiguration.TimeRange(last: nil, start: "2024-01-15", end: "2024-01-16")
                == .range(start: .raw("2024-01-15"), end: .raw("2024-01-16"))
        )
    }

    @Test
    func timeRangeIgnoresEndWithoutStart() {
        #expect(ShowConfiguration.TimeRange(last: nil, start: nil, end: "2024-01-16") == nil)
        #expect(ShowConfiguration.TimeRange(last: nil, start: nil, end: nil) == nil)
    }

    @Test
    func dateRange() {
        let config = ShowConfiguration(
            timeRange: .range(start: .raw("2024-01-15 10:00:00"), end: .raw("2024-01-15 11:00:00"))
        )

        if case .range(let start, let end) = config.timeRange {
            #expect(start == .raw("2024-01-15 10:00:00"))
            #expect(end == .raw("2024-01-15 11:00:00"))
        } else {
            Issue.record("Expected .range time range")
        }
    }

    @Test
    func archivePath() {
        let config = ShowConfiguration(archivePath: "/tmp/test.logarchive")

        #expect(config.archivePath == "/tmp/test.logarchive")
    }
}

@Suite("LogReader Command Building Tests")
struct LogReaderCommandTests {
    let reader = LogReader()

    @Test
    func basicArguments() {
        let config = ShowConfiguration()
        let args = reader.buildArguments(for: config)

        #expect(args[0] == "show")
        #expect(args[1] == "--style")
        #expect(args[2] == "ndjson")
    }

    @Test
    func infoFlag() {
        let config = ShowConfiguration(includeInfo: true)
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--info"))
    }

    @Test
    func debugFlag() {
        let config = ShowConfiguration(includeDebug: true)
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--debug"))
    }

    @Test
    func signpostFlag() {
        let config = ShowConfiguration(includeSignposts: true)
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--signpost"))
    }

    @Test
    func signpostFlagOffByDefault() {
        let config = ShowConfiguration()
        let args = reader.buildArguments(for: config)

        #expect(!args.contains("--signpost"))
    }

    @Test
    func lastDurationArg() {
        let config = ShowConfiguration(timeRange: .last("5m"))
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--last"))
        if let idx = args.firstIndex(of: "--last") {
            #expect(args[idx + 1] == "5m")
        }
    }

    @Test
    func lastBootArg() {
        let config = ShowConfiguration(timeRange: .last("boot"))
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--last"))
        if let idx = args.firstIndex(of: "--last") {
            #expect(args[idx + 1] == "boot")
        }
    }

    @Test
    func startEndArgs() {
        let config = ShowConfiguration(
            timeRange: .range(start: .raw("2024-01-15 10:00:00"), end: .raw("2024-01-15 11:00:00"))
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

    @Test
    func predicateArg() {
        let config = ShowConfiguration(predicate: "processImagePath ENDSWITH \"/Finder\"")
        let args = reader.buildArguments(for: config)

        #expect(args.contains("--predicate"))
        if let idx = args.firstIndex(of: "--predicate") {
            #expect(args[idx + 1] == "processImagePath ENDSWITH \"/Finder\"")
        }
    }

    @Test
    func archivePathArg() {
        let config = ShowConfiguration(
            timeRange: .last("1m"),
            archivePath: "/tmp/test.logarchive"
        )
        let args = reader.buildArguments(for: config)

        #expect(args.last == "/tmp/test.logarchive")
    }

    @Test
    func noInfoDebugFlags() {
        let config = ShowConfiguration(includeInfo: false, includeDebug: false)
        let args = reader.buildArguments(for: config)

        #expect(!args.contains("--info"))
        #expect(!args.contains("--debug"))
    }

    // MARK: - ISO start/end

    private func value(after flag: String, in args: [String]) -> String? {
        args.firstIndex(of: flag).map { args[$0 + 1] }
    }

    @Test
    func isoStartIsPassedAsWholeSecondsRoundedDown() {
        let args = reader
            .buildArguments(for: ShowConfiguration(timeRange: .start(.init("2026-11-01T22:07:07.987654Z"))))
        #expect(value(after: "--start", in: args) == "2026-11-01 22:07:07+0000")
    }

    @Test
    func isoEndIsRoundedUp() {
        let range = ShowConfiguration.TimeRange(
            last: nil,
            start: "2026-11-01T22:07:07.1Z",
            end: "2026-11-01T22:08:00.2Z"
        )
        let args = reader.buildArguments(for: ShowConfiguration(timeRange: range))
        #expect(value(after: "--start", in: args) == "2026-11-01 22:07:07+0000")
        #expect(value(after: "--end", in: args) == "2026-11-01 22:08:01+0000")
    }

    @Test
    func zonedTimestampsAreConvertedToUTC() {
        let args = reader.buildArguments(for: ShowConfiguration(timeRange: .start(.init("2026-11-01 23:07:07+0100"))))
        #expect(value(after: "--start", in: args) == "2026-11-01 22:07:07+0000")
    }

    @Test
    func plainDatesPassThroughUnchanged() {
        let range = ShowConfiguration.TimeRange(last: nil, start: "2024-01-15 10:30:00", end: "2024-01-16")
        let args = reader.buildArguments(for: ShowConfiguration(timeRange: range))
        #expect(value(after: "--start", in: args) == "2024-01-15 10:30:00")
        #expect(value(after: "--end", in: args) == "2024-01-16")
    }

    @Test
    func parseableValuesBecomeExactBounds() throws {
        let iso = try #require(LogTimestamp.parse("2026-11-01T22:07:07.5Z"))
        #expect(ShowConfiguration.TimeRange.Bound("2026-11-01T22:07:07.5Z") == .exact(iso))
        #expect(ShowConfiguration.TimeRange.Bound("2024-01-15 10:30:00") == .raw("2024-01-15 10:30:00"))
        #expect(ShowConfiguration.TimeRange.Bound("2024-01-16") == .raw("2024-01-16"))
    }

    @Test
    func exactBoundsTrimSubSecondEdges() throws {
        let range = try #require(ShowConfiguration.TimeRange(
            last: nil,
            start: "2026-11-01T22:07:07.500000Z",
            end: "2026-11-01T22:07:08.250000Z"
        ))
        let start = try #require(LogTimestamp.parse("2026-11-01T22:07:07.500000Z"))
        #expect(!range.contains(start.addingTimeInterval(-0.000_001)))
        #expect(range.contains(start))
        #expect(range.contains(start.addingTimeInterval(0.75)))
        #expect(!range.contains(start.addingTimeInterval(0.750_001)))
    }

    @Test
    func rawBoundsAndLastAreLeftToLog() {
        let past = Date(timeIntervalSince1970: 0)
        #expect(ShowConfiguration.TimeRange.start(.raw("2024-01-15 10:30:00")).contains(past))
        #expect(ShowConfiguration.TimeRange.last("5m").contains(past))
    }
}
