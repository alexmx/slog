//
//  SignpostFormatter.swift
//  slog
//

import Foundation
import ToonFormat

/// Renders aggregated `os_signpost` intervals in the requested output format.
public enum SignpostFormatter {
    /// Render summaries in the given format. Text formats (plain/compact/color)
    /// use the aligned table; `json`/`toon` emit the structured shape.
    public static func render(
        _ summaries: [SignpostSummary],
        format: OutputFormat,
        orphanEndCount: Int = 0
    ) -> String {
        switch format {
        case .json:
            return renderJSON(summaries)
        case .toon:
            return renderToon(summaries)
        case .plain, .compact, .color:
            return renderTable(summaries, orphanEndCount: orphanEndCount)
        }
    }

    /// Render per-name summaries as an aligned table, with a footer noting
    /// in-flight and orphaned events when present.
    public static func renderTable(
        _ summaries: [SignpostSummary],
        orphanEndCount: Int = 0
    ) -> String {
        guard !summaries.isEmpty else {
            return noResultsMessage()
        }

        let headers = ["interval", "count", "p50", "max", "total", "last args"]
        var rows: [[String]] = [headers]

        for summary in summaries {
            rows.append([
                summary.name,
                String(summary.count),
                formatMs(summary.p50Ms),
                formatMs(summary.maxMs),
                formatMs(summary.totalMs),
                lastArgs(summary)
            ])
        }

        // Column widths from the widest cell in each column.
        let widths = (0..<headers.count).map { col in
            rows.map { $0[col].count }.max() ?? 0
        }

        var lines = rows.map { row in
            row.enumerated()
                .map { idx, cell in cell.padding(toLength: widths[idx], withPad: " ", startingAt: 0) }
                .joined(separator: "  ")
                .trimmingTrailingWhitespace()
        }

        // Footer for in-flight / orphaned events.
        let inFlight = summaries.reduce(0) { $0 + $1.inFlightCount }
        var notes: [String] = []
        if inFlight > 0 {
            notes.append("\(inFlight) in-flight (begin with no end)")
        }
        if orphanEndCount > 0 {
            notes.append("\(orphanEndCount) orphaned end\(orphanEndCount == 1 ? "" : "s") (end with no begin)")
        }
        if !notes.isEmpty {
            lines.append("")
            lines.append("note: " + notes.joined(separator: ", "))
        }

        return lines.joined(separator: "\n")
    }

    /// Hint shown when no intervals were found — points at the common causes.
    public static func noResultsMessage() -> String {
        """
        No signpost intervals found for the given filters.
        
        Check that:
          - the target process emits os_signpost intervals under this subsystem/category
          - for `show`, debug-scoped signposts may need persistence enabled:
              log config --subsystem <subsystem> --mode persist:debug
          - or capture live with `slog stream --signpost` while exercising the app
        """
    }

    // MARK: - Structured formats

    /// Pretty-printed JSON array of `FormattedSignpost` (with occurrences).
    static func renderJSON(_ summaries: [SignpostSummary]) -> String {
        let models = summaries.map { FormattedSignpost(from: $0) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(models) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// TOON-encoded array of `FormattedSignpost` (token-optimized).
    static func renderToon(_ summaries: [SignpostSummary]) -> String {
        let models = summaries.map { FormattedSignpost(from: $0) }
        do {
            let data = try TOONEncoder().encode(models)
            return String(decoding: data, as: UTF8.self)
        } catch {
            return renderJSON(summaries)
        }
    }

    // MARK: - Helpers

    /// Format milliseconds compactly: whole numbers above 100ms, one decimal below.
    static func formatMs(_ value: Double?) -> String {
        guard let value else { return "-" }
        if value >= 100 {
            return String(format: "%.0fms", value)
        }
        return String(format: "%.1fms", value)
    }

    /// The most recent occurrence's interpolated args (empty rendered as "-").
    private static func lastArgs(_ summary: SignpostSummary) -> String {
        let message = summary.occurrences.last?.message ?? ""
        return message.isEmpty ? "-" : message
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last == " " {
            result.removeLast()
        }
        return result
    }
}
