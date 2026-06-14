//
//  StreamConfigurationTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("StreamConfiguration Tests")
struct StreamConfigurationTests {
    @Test
    func defaultConfiguration() {
        let config = StreamConfiguration()

        #expect(config.target == .local)
        #expect(config.predicate == nil)
        #expect(config.includeInfo == true)
        #expect(config.includeDebug == false)
        #expect(config.includeSource == false)
    }

    @Test
    func simulatorTarget() {
        let config = StreamConfiguration(target: .simulator(udid: "ABC-123"))

        if case .simulator(let udid) = config.target {
            #expect(udid == "ABC-123")
        } else {
            Issue.record("Expected .simulator target")
        }
    }

    @Test
    func equality() {
        let a = StreamConfiguration(
            target: .local,
            predicate: "subsystem BEGINSWITH \"com.test\"",
            includeInfo: true,
            includeDebug: true
        )
        let b = StreamConfiguration(
            target: .local,
            predicate: "subsystem BEGINSWITH \"com.test\"",
            includeInfo: true,
            includeDebug: true
        )

        #expect(a == b)
    }
}

@Suite("LogStreamer Command Building Tests")
struct LogStreamerCommandTests {
    let streamer = LogStreamer()

    @Test
    func basicArguments() {
        let config = StreamConfiguration()
        let (_, args) = streamer.buildCommand(for: config)

        #expect(args[0] == "stream")
        #expect(args[1] == "--style")
        #expect(args[2] == "ndjson")
    }

    @Test
    func infoFlag() {
        let config = StreamConfiguration(includeInfo: true)
        let (_, args) = streamer.buildCommand(for: config)

        #expect(args.contains("--info"))
    }

    @Test
    func noInfoFlag() {
        let config = StreamConfiguration(includeInfo: false)
        let (_, args) = streamer.buildCommand(for: config)

        #expect(!args.contains("--info"))
    }

    @Test
    func debugFlag() {
        let config = StreamConfiguration(includeDebug: true)
        let (_, args) = streamer.buildCommand(for: config)

        #expect(args.contains("--debug"))
    }

    @Test
    func sourceFlag() {
        let config = StreamConfiguration(includeSource: true)
        let (_, args) = streamer.buildCommand(for: config)

        #expect(args.contains("--source"))
    }

    @Test
    func noSourceFlag() {
        let config = StreamConfiguration()
        let (_, args) = streamer.buildCommand(for: config)

        #expect(!args.contains("--source"))
    }

    @Test
    func predicateArg() {
        let config = StreamConfiguration(predicate: "subsystem BEGINSWITH \"com.test\"")
        let (_, args) = streamer.buildCommand(for: config)

        #expect(args.contains("--predicate"))
        if let idx = args.firstIndex(of: "--predicate") {
            #expect(args[idx + 1] == "subsystem BEGINSWITH \"com.test\"")
        }
    }

    @Test
    func localTarget() {
        let config = StreamConfiguration(target: .local)
        let (executable, _) = streamer.buildCommand(for: config)

        #expect("\(executable)".contains("log"))
    }

    @Test
    func simulatorTarget() {
        let config = StreamConfiguration(target: .simulator(udid: "TEST-UDID"))
        let (executable, args) = streamer.buildCommand(for: config)

        #expect("\(executable)".contains("xcrun"))
        #expect(args[0] == "simctl")
        #expect(args[1] == "spawn")
        #expect(args[2] == "TEST-UDID")
        #expect(args[3] == "log")
        #expect(args[4] == "stream")
    }

    @Test
    func simulatorPreservesFlags() throws {
        let config = StreamConfiguration(
            target: .simulator(udid: "U"),
            predicate: "subsystem BEGINSWITH \"test\"",
            includeInfo: true,
            includeDebug: true,
            includeSource: true
        )
        let (_, args) = streamer.buildCommand(for: config)

        // After "simctl", "spawn", "U", "log", the stream args should follow
        let logIndex = try #require(args.firstIndex(of: "log"))
        let afterLog = Array(args[(logIndex + 1)...])

        #expect(afterLog.contains("stream"))
        #expect(afterLog.contains("--info"))
        #expect(afterLog.contains("--debug"))
        #expect(afterLog.contains("--source"))
        #expect(afterLog.contains("--predicate"))
    }

    @Test
    func noDebugInfoFlags() {
        let config = StreamConfiguration(includeInfo: false, includeDebug: false)
        let (_, args) = streamer.buildCommand(for: config)

        #expect(!args.contains("--info"))
        #expect(!args.contains("--debug"))
    }
}
