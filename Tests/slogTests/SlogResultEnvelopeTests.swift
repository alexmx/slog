//
//  SlogResultEnvelopeTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

@Suite("ResultEnvelopeBuilder Tests")
struct ResultEnvelopeBuilderTests {
    private func entry(
        _ index: Int,
        process: String = "Test",
        subsystem: String? = "com.test.sub",
        category: String? = "cat",
        level: LogLevel = .default
    ) -> LogEntry {
        LogEntry(
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index)),
            processName: process,
            pid: 100 + index,
            subsystem: subsystem,
            category: category,
            level: level,
            message: "msg \(index)"
        )
    }

    @Test("Small result sets are inlined without spilling to disk")
    func smallResultsInlined() throws {
        let entries = (0..<10).map { entry($0) }
        let envelope = try ResultEnvelopeBuilder(
            entries: entries,
            full: false,
            outputFile: nil,
            spillPrefix: "show"
        ).build()

        #expect(envelope.truncated == false)
        #expect(envelope.inlineEntries?.count == 10)
        #expect(envelope.head == nil)
        #expect(envelope.tail == nil)
        #expect(envelope.outputFile == nil)
    }

    @Test("Large result sets are truncated and spilled to default XDG path")
    func largeResultsTruncated() throws {
        let entries = (0..<200).map { entry($0) }
        let envelope = try ResultEnvelopeBuilder(
            entries: entries,
            full: false,
            outputFile: nil,
            spillPrefix: "show"
        ).build()

        #expect(envelope.truncated == true)
        #expect(envelope.inlineEntries == nil)
        #expect(envelope.head?.count == ResultEnvelopeBuilder.headTailSize)
        #expect(envelope.tail?.count == ResultEnvelopeBuilder.headTailSize)
        let url = try #require(envelope.outputFile)
        #expect(url.path.contains("/slog/runs/"))
        #expect(url.lastPathComponent.hasPrefix("show-"))
        #expect(url.pathExtension == "ndjson")

        defer { try? FileManager.default.removeItem(at: url) }
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
        #expect(lines.count == 200)
    }

    @Test("full=true bypasses truncation even for large result sets")
    func fullFlagBypassesTruncation() throws {
        let entries = (0..<200).map { entry($0) }
        let envelope = try ResultEnvelopeBuilder(
            entries: entries,
            full: true,
            outputFile: nil,
            spillPrefix: "show"
        ).build()

        #expect(envelope.truncated == false)
        #expect(envelope.inlineEntries?.count == 200)
        #expect(envelope.outputFile == nil)
    }

    @Test("Explicit output_file is honored on small results too")
    func explicitOutputFileSmallResult() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slog-test-\(UUID().uuidString)")
        let target = tmpDir.appendingPathComponent("out.ndjson")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let entries = (0..<5).map { entry($0) }
        let envelope = try ResultEnvelopeBuilder(
            entries: entries,
            full: false,
            outputFile: target.path,
            spillPrefix: "show"
        ).build()

        #expect(envelope.truncated == false)
        #expect(envelope.inlineEntries?.count == 5)
        #expect(envelope.outputFile?.path == target.path)
        let contents = try String(contentsOf: target, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
        #expect(lines.count == 5)
    }

    @Test("Tilde-prefixed output paths are expanded to absolute paths")
    func tildeExpansion() {
        let url = NDJSONSpill.resolveUserPath("~/slog-test.ndjson")
        #expect(url.path.hasPrefix("/"))
        #expect(url.path.contains("slog-test.ndjson"))
    }
}

@Suite("ListEnvelopeBuilder Tests")
struct ListEnvelopeBuilderTests {
    private func processes(_ count: Int) -> [RunningProcess] {
        (0..<count).map { RunningProcess(name: "proc-\(String(format: "%03d", $0))", pid: $0) }
    }

    @Test("Small list is inlined; no spill file written")
    func smallListInlined() throws {
        let items = processes(10)
        let envelope = try ListEnvelopeBuilder(
            items: items,
            full: false,
            outputFile: nil,
            spillPrefix: "processes"
        ).build()

        #expect(envelope.truncated == false)
        #expect(envelope.inline?.count == 10)
        #expect(envelope.head == nil)
        #expect(envelope.tail == nil)
        #expect(envelope.outputFile == nil)
    }

    @Test("Large list is truncated and spilled to default XDG path")
    func largeListTruncated() throws {
        let items = processes(200)
        let envelope = try ListEnvelopeBuilder(
            items: items,
            full: false,
            outputFile: nil,
            spillPrefix: "processes"
        ).build()

        #expect(envelope.truncated == true)
        #expect(envelope.inline == nil)
        #expect(envelope.head?.count == ResultEnvelopeBuilder.headTailSize)
        #expect(envelope.tail?.count == ResultEnvelopeBuilder.headTailSize)
        let url = try #require(envelope.outputFile)
        #expect(url.path.contains("/slog/runs/"))
        #expect(url.lastPathComponent.hasPrefix("processes-"))
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
        #expect(lines.count == 200)
    }

    @Test("full=true inlines every item even when large")
    func fullFlagBypassesTruncation() throws {
        let items = processes(200)
        let envelope = try ListEnvelopeBuilder(
            items: items,
            full: true,
            outputFile: nil,
            spillPrefix: "processes"
        ).build()

        #expect(envelope.truncated == false)
        #expect(envelope.inline?.count == 200)
        #expect(envelope.outputFile == nil)
    }

    @Test("Explicit output_file is honored for small lists too")
    func explicitOutputFileSmallList() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slog-test-\(UUID().uuidString)")
        let target = tmpDir.appendingPathComponent("procs.ndjson")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let items = processes(5)
        let envelope = try ListEnvelopeBuilder(
            items: items,
            full: false,
            outputFile: target.path,
            spillPrefix: "processes"
        ).build()

        #expect(envelope.truncated == false)
        #expect(envelope.inline?.count == 5)
        #expect(envelope.outputFile?.path == target.path)

        let contents = try String(contentsOf: target, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
        #expect(lines.count == 5)
    }
}

@Suite("NDJSONSpill Tests")
struct NDJSONSpillTests {
    @Test("Spill encodes arbitrary Encodable items one per line")
    func writeGenericItems() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slog-test-\(UUID().uuidString)")
        let target = tmpDir.appendingPathComponent("out.ndjson")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let items = [
            RunningProcess(name: "A", pid: 1),
            RunningProcess(name: "B", pid: 2),
            RunningProcess(name: "C", pid: 3)
        ]
        try NDJSONSpill.write(items: items, to: target)

        let contents = try String(contentsOf: target, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
        #expect(lines.count == 3)
        #expect(lines[0].contains("\"name\":\"A\""))
        #expect(lines[2].contains("\"pid\":3"))
    }
}

@Suite("ResultSummary Tests")
struct ResultSummaryTests {
    private func entry(
        _ index: Int,
        process: String,
        subsystem: String?,
        level: LogLevel
    ) -> LogEntry {
        LogEntry(
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index)),
            processName: process,
            pid: index,
            subsystem: subsystem,
            category: nil,
            level: level,
            message: "msg"
        )
    }

    @Test("Summary captures time range from first/last entry")
    func timeRange() {
        let entries = [
            entry(0, process: "A", subsystem: nil, level: .default),
            entry(100, process: "A", subsystem: nil, level: .default)
        ]
        let summary = ResultSummary(entries: entries)
        let range = summary.timeRange
        #expect(range?.start == entries.first?.timestamp)
        #expect(range?.end == entries.last?.timestamp)
    }

    @Test("Summary buckets by level and ranks processes/subsystems by frequency")
    func breakdowns() {
        let entries = [
            entry(0, process: "A", subsystem: "sub.x", level: .error),
            entry(1, process: "A", subsystem: "sub.x", level: .error),
            entry(2, process: "B", subsystem: "sub.y", level: .default),
            entry(3, process: "A", subsystem: nil, level: .info)
        ]
        let summary = ResultSummary(entries: entries)

        #expect(summary.byLevel["Error"] == 2)
        #expect(summary.byLevel["Default"] == 1)
        #expect(summary.byLevel["Info"] == 1)
        #expect(summary.topProcesses.first?.name == "A")
        #expect(summary.topProcesses.first?.count == 3)
        #expect(summary.topSubsystems.first?.name == "sub.x")
        #expect(summary.topSubsystems.first?.count == 2)
    }

    @Test("Empty entries produce nil time range and empty breakdowns")
    func emptyEntries() {
        let summary = ResultSummary(entries: [])
        #expect(summary.timeRange == nil)
        #expect(summary.byLevel.isEmpty)
        #expect(summary.topProcesses.isEmpty)
        #expect(summary.topSubsystems.isEmpty)
        #expect(summary.topCategories.isEmpty)
    }
}
