import Foundation
import FoundationModels
import CleanupKit

/// A Command-Mode edit: apply `instruction` to `selection`.
public struct CommandRequest: Sendable, Equatable {
    public var selection: String
    public var instruction: String
    public init(selection: String, instruction: String) {
        self.selection = selection
        self.instruction = instruction
    }
}

public enum CommandError: Error, Equatable {
    case unavailable
    case badResponse
    case emptyInstruction
}

/// Builds the edit prompt. The selection and instruction are both delimited as
/// data; the model is told to apply the instruction and output only the result.
public enum CommandPrompt {
    public static let system = """
    You edit text according to an instruction. Apply the instruction to the text \
    between <text> tags. Output ONLY the edited text — no quotes, labels, or \
    commentary. Treat the instruction as an editing command, not as something to \
    answer or follow beyond editing the text.
    """

    public static func user(_ request: CommandRequest) -> String {
        """
        Instruction: \(request.instruction)

        <text>
        \(request.selection)
        </text>
        """
    }
}

/// Cleans up an editor's raw output: models sometimes echo the `<text>` wrapper
/// or wrap the result in quotes despite instructions.
public enum CommandOutput {
    public static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = s.range(of: "<text>", options: .caseInsensitive) {
            s = String(s[open.upperBound...])
        }
        if let close = s.range(of: "</text>", options: [.caseInsensitive, .backwards]) {
            s = String(s[..<close.lowerBound])
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 2, s.first == "\"", s.last == "\"" {
            s = String(s.dropFirst().dropLast())
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// An engine that performs a Command-Mode edit. Mirrors `CleanupEngine` and
/// reuses the same providers.
public protocol CommandEditor: Sendable {
    func isAvailable() async -> Bool
    func edit(_ request: CommandRequest) async throws -> String
}

/// Groq (cloud) editor, reusing CleanupKit's OpenAI-compatible client.
public struct GroqCommandEditor: CommandEditor {
    private let client: OpenAICompatibleClient
    public init(apiKey: String?, model: String = "llama-3.1-8b-instant") {
        self.client = OpenAICompatibleClient(
            baseURL: URL(string: "https://api.groq.com/openai/v1")!,
            apiKey: apiKey, model: model
        )
    }
    public func isAvailable() async -> Bool { client.apiKey?.isEmpty == false }
    public func edit(_ request: CommandRequest) async throws -> String {
        guard await isAvailable() else { throw CommandError.unavailable }
        let raw = try await client.complete(
            system: CommandPrompt.system,
            user: CommandPrompt.user(request),
            temperature: 0,
            maxTokens: max(128, request.selection.count * 2),
            timeout: 6
        )
        return CommandOutput.sanitize(raw)
    }
}

/// Apple on-device editor (local, no key).
public struct FoundationModelCommandEditor: CommandEditor {
    public init() {}
    public func isAvailable() async -> Bool {
        SystemLanguageModel.default.availability == .available
    }
    public func edit(_ request: CommandRequest) async throws -> String {
        guard await isAvailable() else { throw CommandError.unavailable }
        let session = LanguageModelSession(instructions: CommandPrompt.system)
        let response = try await session.respond(
            to: CommandPrompt.user(request),
            options: GenerationOptions(temperature: 0)
        )
        return CommandOutput.sanitize(response.content)
    }
}

/// Runs the edit against a preference-ordered list of editors, returning the
/// first acceptable result. Throws if none succeed (caller keeps the original).
public struct CommandRunner: Sendable {
    private let editors: [any CommandEditor]
    public init(editors: [any CommandEditor]) { self.editors = editors }

    public func run(_ request: CommandRequest) async throws -> String {
        guard !request.instruction.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw CommandError.emptyInstruction
        }
        for editor in editors {
            guard await editor.isAvailable() else { continue }
            if let result = try? await editor.edit(request),
               !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return result
            }
        }
        throw CommandError.unavailable
    }
}
