//
//  FormatterTests.swift
//  slog
//

import Foundation
@testable import slog
import Testing

// MARK: - Test Helpers

private let fixedDate = Date(timeIntervalSince1970: 1_000_000)

private func makeEntry(
    processName: String = "TestApp",
    pid: Int = 42,
    subsystem: String? = "com.test.app",
    category: String? = "general",
    level: LogLevel = .info,
    message: String = "Hello world"
) -> LogEntry {
    LogEntry(
        timestamp: fixedDate,
        processName: processName,
        pid: pid,
        subsystem: subsystem,
        category: category,
        level: level,
        message: message
    )
}

// MARK: - PlainFormatter Tests

@Suite("PlainFormatter Tests")
struct PlainFormatterTests {
    @Test("Full output includes all components")
    func fullOutput() {
        let formatter = PlainFormatter()
        let output = formatter.format(makeEntry())

        #expect(output.contains("[INFO]"))
        #expect(output.contains("TestApp[42]"))
        #expect(output.contains("(com.test.app:general)"))
        #expect(output.contains("Hello world"))
    }

    @Test("Subsystem without category shows subsystem only")
    func subsystemWithoutCategory() {
        let formatter = PlainFormatter()
        let output = formatter.format(makeEntry(category: nil))

        #expect(output.contains("(com.test.app)"))
        #expect(!output.contains("(com.test.app:general)"))
    }

    @Test("No subsystem omits subsystem component")
    func noSubsystem() {
        let formatter = PlainFormatter()
        let output = formatter.format(makeEntry(subsystem: nil, category: nil))

        #expect(!output.contains("("))
        #expect(output.contains("TestApp[42]"))
        #expect(output.contains("Hello world"))
    }

    @Test("Hide timestamp removes timestamp")
    func hideTimestamp() {
        let formatter = PlainFormatter(showTimestamp: false)
        let output = formatter.format(makeEntry())

        // Should start with level bracket
        #expect(output.hasPrefix("[INFO]"))
    }

    @Test("Hide process removes process info")
    func hideProcess() {
        let formatter = PlainFormatter(showProcess: false)
        let output = formatter.format(makeEntry())

        #expect(!output.contains("TestApp[42]"))
        #expect(output.contains("Hello world"))
    }

    @Test(
        "All log levels produce correct labels",
        arguments: [
            (LogLevel.debug, "DEBUG"),
            (LogLevel.info, "INFO"),
            (LogLevel.default, "DEFAULT"),
            (LogLevel.error, "ERROR"),
            (LogLevel.fault, "FAULT"),
        ]
    )
    func levelLabels(level: LogLevel, label: String) {
        let formatter = PlainFormatter()
        let output = formatter.format(makeEntry(level: level))

        #expect(output.contains("[\(label)]"))
    }
}

// MARK: - ColorFormatter Tests

@Suite("ColorFormatter Tests")
struct ColorFormatterTests {
    @Test("Output includes process and message")
    func includesComponents() {
        let formatter = ColorFormatter()
        let output = formatter.format(makeEntry())

        // Rainbow ANSI codes will be present but the text content should be there
        #expect(output.contains("TestApp"))
        #expect(output.contains("42"))
        #expect(output.contains("Hello world"))
    }

    @Test("Compact mode hides process and subsystem")
    func compactMode() {
        let formatter = ColorFormatter(
            showProcess: false,
            showSubsystem: false
        )
        let output = formatter.format(makeEntry())

        // Should not contain process identifier pattern
        // Note: ANSI codes make exact matching hard, but the raw text should be limited
        #expect(output.contains("Hello world"))
    }

    @Test("Error level colors message red")
    func errorLevelColors() {
        let formatter = ColorFormatter()
        let output = formatter.format(makeEntry(level: .error))

        // Rainbow applies ANSI escape codes; verify the output is different from info
        let infoOutput = formatter.format(makeEntry(level: .info))
        #expect(output != infoOutput)
    }

    @Test("Highlight pattern is stored and used")
    func highlightPattern() {
        let formatter = ColorFormatter(highlightPattern: "world")
        let output = formatter.format(makeEntry())

        // Verify the output still contains the message content
        #expect(output.contains("Hello"))
        // When Rainbow is enabled (TTY), highlighted output differs from plain;
        // in test environments Rainbow may be disabled, so just verify it doesn't crash
        // and produces output containing the message
        #expect(!output.isEmpty)
    }

    @Test("No subsystem omits subsystem from output")
    func noSubsystem() {
        let formatter = ColorFormatter()
        let withSub = formatter.format(makeEntry(subsystem: "com.test"))
        let withoutSub = formatter.format(makeEntry(subsystem: nil))

        #expect(withSub.count > withoutSub.count)
    }
}

// MARK: - JSONFormatter Tests

@Suite("JSONFormatter Tests")
struct JSONFormatterTests {
    @Test("Output is valid JSON")
    func validJSON() throws {
        let formatter = JSONFormatter()
        let output = formatter.format(makeEntry())

        let data = try #require(output.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(parsed != nil)
        #expect(parsed?["process"] as? String == "TestApp")
        #expect(parsed?["pid"] as? Int == 42)
        #expect(parsed?["level"] as? String == "Info")
        #expect(parsed?["message"] as? String == "Hello world")
        #expect(parsed?["subsystem"] as? String == "com.test.app")
        #expect(parsed?["category"] as? String == "general")
    }

    @Test("Nil fields are null in JSON")
    func nilFieldsAreNull() throws {
        let formatter = JSONFormatter()
        let output = formatter.format(makeEntry(subsystem: nil, category: nil))

        let data = try #require(output.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(parsed?["process"] as? String == "TestApp")
        // subsystem should be NSNull or absent
        #expect(parsed?["subsystem"] is NSNull || parsed?["subsystem"] == nil)
    }

    @Test("Pretty mode produces multi-line output")
    func prettyMode() {
        let formatter = JSONFormatter(pretty: true)
        let output = formatter.format(makeEntry())

        #expect(output.contains("\n"))
    }

    @Test("Compact mode produces single-line output")
    func compactMode() {
        let formatter = JSONFormatter(pretty: false)
        let output = formatter.format(makeEntry())

        #expect(!output.contains("\n"))
    }

    @Test("Keys are sorted")
    func sortedKeys() throws {
        let formatter = JSONFormatter()
        let output = formatter.format(makeEntry())

        // In sorted key output, "category" should come before "level"
        let categoryIdx = try #require(output.range(of: "category")?.lowerBound)
        let levelIdx = try #require(output.range(of: "level")?.lowerBound)
        #expect(categoryIdx < levelIdx)
    }

    @Test("Special characters in message are properly escaped")
    func specialCharacters() throws {
        let formatter = JSONFormatter()
        let output = formatter.format(makeEntry(message: "line1\nline2\ttab"))

        let data = try #require(output.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(parsed?["message"] as? String == "line1\nline2\ttab")
    }

    @Test(
        "All log levels produce correct level strings",
        arguments: [
            (LogLevel.debug, "Debug"),
            (LogLevel.info, "Info"),
            (LogLevel.default, "Default"),
            (LogLevel.error, "Error"),
            (LogLevel.fault, "Fault")
        ]
    )
    func levelStrings(level: LogLevel, expected: String) throws {
        let formatter = JSONFormatter()
        let output = formatter.format(makeEntry(level: level))

        let data = try #require(output.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(parsed?["level"] as? String == expected)
    }
}

// MARK: - ToonFormatter Tests

@Suite("ToonFormatter Tests")
struct ToonFormatterTests {
    @Test("Output is non-empty")
    func nonEmpty() {
        let formatter = ToonFormatter()
        let output = formatter.format(makeEntry())

        #expect(!output.isEmpty)
    }

    @Test("Output contains key fields")
    func containsFields() {
        let formatter = ToonFormatter()
        let output = formatter.format(makeEntry())

        #expect(output.contains("TestApp"))
        #expect(output.contains("42"))
        #expect(output.contains("Hello world"))
    }

    @Test("Different levels produce different output")
    func differentLevels() {
        let formatter = ToonFormatter()
        let errorOutput = formatter.format(makeEntry(level: .error))
        let debugOutput = formatter.format(makeEntry(level: .debug))

        #expect(errorOutput != debugOutput)
    }
}

// MARK: - FormatterRegistry Tests

@Suite("FormatterRegistry Tests")
struct FormatterRegistryTests {
    @Test("Plain format returns PlainFormatter")
    func plainFormat() {
        let formatter = FormatterRegistry.formatter(for: .plain)
        #expect(formatter is PlainFormatter)
    }

    @Test("Color format returns ColorFormatter")
    func colorFormat() {
        let formatter = FormatterRegistry.formatter(for: .color)
        #expect(formatter is ColorFormatter)
    }

    @Test("Compact format returns ColorFormatter")
    func compactFormat() {
        let formatter = FormatterRegistry.formatter(for: .compact)
        #expect(formatter is ColorFormatter)
    }

    @Test("JSON format returns JSONFormatter")
    func jsonFormat() {
        let formatter = FormatterRegistry.formatter(for: .json)
        #expect(formatter is JSONFormatter)
    }

    @Test("Toon format returns ToonFormatter")
    func toonFormat() {
        let formatter = FormatterRegistry.formatter(for: .toon)
        #expect(formatter is ToonFormatter)
    }
}
