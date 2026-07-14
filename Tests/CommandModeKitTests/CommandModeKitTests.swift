import XCTest
@testable import CommandModeKit

final class CommandPromptTests: XCTestCase {
    func testUserEmbedsInstructionAndText() {
        let req = CommandRequest(selection: "hello world", instruction: "make it formal")
        let user = CommandPrompt.user(req)
        XCTAssertTrue(user.contains("make it formal"))
        XCTAssertTrue(user.contains("<text>"))
        XCTAssertTrue(user.contains("hello world"))
    }

    func testSystemHasInjectionGuard() {
        XCTAssertTrue(CommandPrompt.system.lowercased().contains("not as something to"))
    }
}

final class CommandOutputTests: XCTestCase {
    func testStripsTextWrapper() {
        let raw = "<text>\nHello, could you send it?\n</text>"
        XCTAssertEqual(CommandOutput.sanitize(raw), "Hello, could you send it?")
    }

    func testStripsSurroundingQuotes() {
        XCTAssertEqual(CommandOutput.sanitize("\"formal text\""), "formal text")
    }

    func testLeavesCleanTextAlone() {
        XCTAssertEqual(CommandOutput.sanitize("  already clean  "), "already clean")
    }
}

final class CommandRunnerTests: XCTestCase {
    /// A stub editor so the runner logic is testable without a live model.
    private struct StubEditor: CommandEditor {
        let available: Bool
        let output: String?
        func isAvailable() async -> Bool { available }
        func edit(_ request: CommandRequest) async throws -> String {
            guard let output else { throw CommandError.badResponse }
            return output
        }
    }

    func testEmptyInstructionThrows() async {
        let runner = CommandRunner(editors: [StubEditor(available: true, output: "x")])
        do {
            _ = try await runner.run(CommandRequest(selection: "text", instruction: "  "))
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? CommandError, .emptyInstruction)
        }
    }

    func testSkipsUnavailableAndUsesNext() async throws {
        let runner = CommandRunner(editors: [
            StubEditor(available: false, output: "first"),
            StubEditor(available: true, output: "second"),
        ])
        let result = try await runner.run(CommandRequest(selection: "t", instruction: "do it"))
        XCTAssertEqual(result, "second")
    }

    func testFallsThroughFailingEditor() async throws {
        let runner = CommandRunner(editors: [
            StubEditor(available: true, output: nil),      // throws
            StubEditor(available: true, output: "ok"),
        ])
        let result = try await runner.run(CommandRequest(selection: "t", instruction: "do it"))
        XCTAssertEqual(result, "ok")
    }

    func testAllFailThrows() async {
        let runner = CommandRunner(editors: [StubEditor(available: false, output: nil)])
        do {
            _ = try await runner.run(CommandRequest(selection: "t", instruction: "do it"))
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? CommandError, .unavailable)
        }
    }
}

/// Live edit via Apple Foundation Models (local). Gated like the other live tests.
final class FoundationModelCommandEditorTests: XCTestCase {
    func testLiveEdit() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FLOWCLONE_RUN_LLM_TEST"] == "1",
            "Set FLOWCLONE_RUN_LLM_TEST=1 to run the live command-edit test"
        )
        let editor = FoundationModelCommandEditor()
        guard await editor.isAvailable() else { throw XCTSkip("Apple FM unavailable") }
        let edited = try await editor.edit(CommandRequest(
            selection: "hey can u send me the thing",
            instruction: "make this more formal"
        ))
        print("command edit: \(edited)")
        XCTAssertFalse(edited.isEmpty)
        // A formal rewrite shouldn't keep the casual "u".
        XCTAssertFalse(edited.lowercased().split(separator: " ").contains("u"))
    }
}
