//
//  SlogResultEnvelope.swift
//  slog
//

import Foundation

/// Aggregate stats for a result set. Lets callers decide whether to fetch the
/// full NDJSON spill or move on without ever reading it.
struct ResultSummary: Encodable {
    let timeRange: TimeRange?
    let byLevel: [String: Int]
    let topProcesses: [Bucket]
    let topSubsystems: [Bucket]
    let topCategories: [Bucket]

    struct TimeRange: Encodable {
        let start: Date
        let end: Date
    }

    struct Bucket: Encodable {
        let name: String
        let count: Int
    }

    enum CodingKeys: String, CodingKey {
        case timeRange = "time_range"
        case byLevel = "by_level"
        case topProcesses = "top_processes"
        case topSubsystems = "top_subsystems"
        case topCategories = "top_categories"
    }

    init(entries: [LogEntry], topN: Int = 10) {
        var accumulator = SummaryAccumulator()
        for entry in entries {
            accumulator.add(entry)
        }
        self = accumulator.build(topN: topN)
    }

    fileprivate init(
        timeRange: TimeRange?,
        byLevel: [String: Int],
        topProcesses: [Bucket],
        topSubsystems: [Bucket],
        topCategories: [Bucket]
    ) {
        self.timeRange = timeRange
        self.byLevel = byLevel
        self.topProcesses = topProcesses
        self.topSubsystems = topSubsystems
        self.topCategories = topCategories
    }

    fileprivate static func topBuckets(_ counts: [String: Int], limit: Int) -> [Bucket] {
        counts
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .prefix(limit)
            .map { Bucket(name: $0.key, count: $0.value) }
    }
}

/// Streaming counterpart to `ResultSummary` — accumulates one entry at a time
/// so we can compute the full-population summary without retaining every
/// `LogEntry` in memory. Used by `slog_show` to scan past the `count` cap for
/// aggregate accuracy.
struct SummaryAccumulator {
    private(set) var firstTimestamp: Date?
    private(set) var lastTimestamp: Date?
    private var levels: [String: Int] = [:]
    private var processes: [String: Int] = [:]
    private var subsystems: [String: Int] = [:]
    private var categories: [String: Int] = [:]
    private(set) var count: Int = 0

    mutating func add(_ entry: LogEntry) {
        count += 1
        if firstTimestamp == nil {
            firstTimestamp = entry.timestamp
        }
        lastTimestamp = entry.timestamp
        levels[entry.level.rawValue, default: 0] += 1
        processes[entry.processName, default: 0] += 1
        if let sub = entry.subsystem, !sub.isEmpty {
            subsystems[sub, default: 0] += 1
        }
        if let cat = entry.category, !cat.isEmpty {
            categories[cat, default: 0] += 1
        }
    }

    func build(topN: Int = 10) -> ResultSummary {
        let range: ResultSummary.TimeRange?
        if let first = firstTimestamp, let last = lastTimestamp {
            range = ResultSummary.TimeRange(start: first, end: last)
        } else {
            range = nil
        }
        return ResultSummary(
            timeRange: range,
            byLevel: levels,
            topProcesses: ResultSummary.topBuckets(processes, limit: topN),
            topSubsystems: ResultSummary.topBuckets(subsystems, limit: topN),
            topCategories: ResultSummary.topBuckets(categories, limit: topN)
        )
    }
}

/// Writes log entries to disk as newline-delimited JSON so callers can use
/// `Read offset/limit` (or `jq`) to drill in selectively, rather than
/// re-parsing one giant inline blob.
enum NDJSONSpill {
    enum SpillError: Error, LocalizedError {
        case writeFailed(URL, String)
        case readFailed(URL, String)
        case parseError(URL, Int, String)

        var errorDescription: String? {
            switch self {
            case let .writeFailed(url, message):
                "Failed to write NDJSON to \(url.path): \(message)"
            case let .readFailed(url, message):
                "Failed to read NDJSON from \(url.path): \(message)"
            case let .parseError(url, line, message):
                "Failed to parse NDJSON at \(url.path):\(line): \(message)"
            }
        }
    }

    static func write(items: [some Encodable], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        var data = Data()
        data.reserveCapacity(items.count * 256)
        for item in items {
            data.append(try encoder.encode(item))
            data.append(0x0a)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw SpillError.writeFailed(url, error.localizedDescription)
        }
    }

    /// Async stream of `LogEntry` decoded one-per-line from an NDJSON file —
    /// the symmetric reader for spill files written by `write(items:to:)`.
    /// Surfaces parse failures with the offending line number for fast triage.
    static func readEntries(from url: URL) -> AsyncThrowingStream<LogEntry, Error> {
        AsyncThrowingStream { continuation in
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                continuation.finish(
                    throwing: SpillError.readFailed(url, "file not found or unreadable")
                )
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let task = Task {
                do {
                    var lineNumber = 0
                    for try await line in url.lines {
                        lineNumber += 1
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty { continue }
                        guard let data = trimmed.data(using: .utf8) else { continue }
                        do {
                            let entry = try decoder.decode(LogEntry.self, from: data)
                            continuation.yield(entry)
                        } catch {
                            continuation.finish(
                                throwing: SpillError.parseError(url, lineNumber, error.localizedDescription)
                            )
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Generate an auto path under `$XDG_CACHE_HOME/slog/runs/` when the caller
    /// didn't supply `output_file`. `now` is injectable for tests.
    static func defaultURL(prefix: String, now: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss-SSS"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: now)
        return XDGDirectories.runsDirectory
            .appendingPathComponent("\(prefix)-\(stamp).ndjson")
    }

    /// Expand `~` and normalize to an absolute URL for caller-supplied paths.
    static func resolveUserPath(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
}

/// Generic truncate-or-inline + spill logic for any Encodable list. Used by
/// list-style tools (`slog_list_processes`) that don't need a summary.
struct ListEnvelopeBuilder<T: Encodable> {
    let items: [T]
    let full: Bool
    let outputFile: String?
    /// Prefix for the auto-generated NDJSON filename (e.g. `processes`).
    let spillPrefix: String

    struct Output {
        let truncated: Bool
        let inline: [T]?
        let head: [T]?
        let tail: [T]?
        let outputFile: URL?
    }

    func build() throws -> Output {
        let explicitURL = outputFile.map { NDJSONSpill.resolveUserPath($0) }

        if full || items.count <= ResultEnvelopeBuilder.inlineThreshold {
            if let url = explicitURL {
                try NDJSONSpill.write(items: items, to: url)
            }
            return Output(
                truncated: false,
                inline: items,
                head: nil,
                tail: nil,
                outputFile: explicitURL
            )
        }

        let spillURL = explicitURL ?? NDJSONSpill.defaultURL(prefix: spillPrefix)
        try NDJSONSpill.write(items: items, to: spillURL)

        let headTailSize = ResultEnvelopeBuilder.headTailSize
        let head = Array(items.prefix(headTailSize))
        let tailStart = max(items.count - headTailSize, headTailSize)
        let tail = Array(items[tailStart..<items.count])

        return Output(
            truncated: true,
            inline: nil,
            head: head,
            tail: tail,
            outputFile: spillURL
        )
    }
}

/// Decides which slice of a result set to inline and which to spill, given the
/// caller's preferences. Single source of truth so `slog_show` and `slog_stream`
/// behave identically.
struct ResultEnvelopeBuilder {
    /// Below this, the full result is small enough to inline without truncation.
    static let inlineThreshold = 50
    /// How many entries from the start/end to surface when truncated.
    static let headTailSize = 10

    let entries: [LogEntry]
    let full: Bool
    let outputFile: String?
    /// Prefix for the auto-generated NDJSON filename (`show`, `stream`).
    let spillPrefix: String

    struct Output {
        let truncated: Bool
        let inlineEntries: [LogEntry]?
        let head: [LogEntry]?
        let tail: [LogEntry]?
        let summary: ResultSummary
        let outputFile: URL?
    }

    func build() throws -> Output {
        let summary = ResultSummary(entries: entries)
        let explicitURL = outputFile.map { NDJSONSpill.resolveUserPath($0) }

        // Inline path: caller asked for full, or the set is already small.
        if full || entries.count <= Self.inlineThreshold {
            if let url = explicitURL {
                try NDJSONSpill.write(items: entries, to: url)
            }
            return Output(
                truncated: false,
                inlineEntries: entries,
                head: nil,
                tail: nil,
                summary: summary,
                outputFile: explicitURL
            )
        }

        // Truncated path: always spill so the caller can drill in.
        let spillURL = explicitURL ?? NDJSONSpill.defaultURL(prefix: spillPrefix)
        try NDJSONSpill.write(items: entries, to: spillURL)

        let head = Array(entries.prefix(Self.headTailSize))
        let tailStart = max(entries.count - Self.headTailSize, Self.headTailSize)
        let tail = Array(entries[tailStart..<entries.count])

        return Output(
            truncated: true,
            inlineEntries: nil,
            head: head,
            tail: tail,
            summary: summary,
            outputFile: spillURL
        )
    }
}
