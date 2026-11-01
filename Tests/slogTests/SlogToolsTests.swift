//
//  SlogToolsTests.swift
//  slog
//

import Foundation
@testable import slog
import SwiftMCP
import Testing

@Suite("SlogTools respond Tests")
struct SlogToolsTests {
    private struct Sample: Encodable {
        let count: Int
    }

    private struct Opaque: Error {}

    /// Decode the JSON object a tool returned.
    private func payload(_ result: MCPToolResult) throws -> [String: Any] {
        guard case .text(let text) = result else {
            Issue.record("expected a text result")
            return [:]
        }
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test
    func successEncodesTheResult() async throws {
        let result = await SlogTools.respond { Sample(count: 3) }
        let json = try payload(result)
        #expect(json["count"] as? Int == 3)
        #expect(json["error"] == nil)
    }

    @Test
    func validationErrorOmitsTryDoctor() async throws {
        let result = await SlogTools.respond { () throws -> Sample in
            throw SlogTools.ToolError(message: "bad args")
        }
        let json = try payload(result)
        #expect(json["error"] as? String == "bad args")
        #expect(json["try_doctor"] == nil)
    }

    @Test
    func systemErrorSetsTryDoctor() async throws {
        let result = await SlogTools.respond { () throws -> Sample in
            throw SlogTools.ToolError.system(SystemQueryError.parseError("simctl broke"))
        }
        let json = try payload(result)
        #expect(json["error"] as? String == "System query error: simctl broke")
        #expect(json["try_doctor"] as? Bool == true)
    }

    @Test
    func otherErrorsBecomeErrorPayloadWithoutTryDoctor() async throws {
        let result = await SlogTools.respond { () throws -> Sample in
            throw FilterSetupError.invalidRegex(field: "grep", reason: "unbalanced")
        }
        let json = try payload(result)
        #expect(json["error"] as? String == "Invalid 'grep' regex: unbalanced")
        #expect(json["try_doctor"] == nil)
    }

    @Test
    func errorsWithoutDescriptionStillProduceErrorPayload() async throws {
        let result = await SlogTools.respond { () throws -> Sample in
            throw Opaque()
        }
        let json = try payload(result)
        #expect(json["error"] is String)
    }

    // MARK: - parseLevel

    @Test
    func parseLevelAcceptsAnyCase() throws {
        #expect(try SlogTools.parseLevel("Error") == .error)
        #expect(try SlogTools.parseLevel("debug") == .debug)
    }

    @Test
    func parseLevelPassesNilThrough() throws {
        #expect(try SlogTools.parseLevel(nil) == nil)
    }

    @Test
    func parseLevelRejectsUnknownValues() {
        #expect {
            try SlogTools.parseLevel("warn")
        } throws: { error in
            (error as? SlogTools.ToolError)?.message
                == "Invalid 'level' 'warn'. Expected one of: debug, info, default, error, fault"
        }
    }
}
