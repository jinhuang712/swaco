import Foundation
import Swaco

/// Shows the model a few tools and one tool for finding the rest.
///
/// A template, not a shipped extension: which tools are worth the model's
/// attention, and how they are described, is a product decision that changes
/// with every app and every model.
///
/// The doors it uses are rewriting the request, to hand over a shorter list,
/// and an ordinary tool for the discovery itself.
public struct ProgressiveDisclosure: Extension {
    public let name = "disclosure"
    private let alwaysShow: Set<String>
    private let revealed: Revealed

    /// - Parameters:
    ///   - alwaysShow: the names the model sees from the start. The discovery
    ///     tool is added to these.
    ///   - revealed: what the model has since asked for, shared with the
    ///     discovery tool.
    public init(alwaysShow: Set<String>, revealed: Revealed) {
        self.alwaysShow = alwaysShow
        self.revealed = revealed
    }

    public func beforeRequest(
        _ request: ModelRequest,
        in context: ExtensionContext
    ) async -> Decision<ModelRequest> {
        let shown = alwaysShow.union([Discover.toolName]).union(await revealed.names)
        let fewer = request.tools.filter { shown.contains($0.name) }
        guard fewer.count != request.tools.count else { return .pass }
        return .rewrite(ModelRequest(messages: request.messages, tools: fewer))
    }

    /// What the model has asked to see. Held apart from the extension because
    /// the tool writes to it and the extension reads it.
    public actor Revealed {
        private var shown: Set<String> = []
        public init() {}
        public var names: Set<String> { shown }
        public func reveal(_ names: [String]) { shown.formUnion(names) }
    }

    /// The tool the model uses to find what it has not been shown.
    public struct Discover: Tool {
        public static let toolName = "find_tools"
        public let name = Discover.toolName
        public let description = "Find tools that are available but not listed"
        public let access = ToolAccess.readOnly
        public let parameters = """
        {"type":"object","properties":{\
        "need":{"type":"string","description":"What you are trying to do"}},\
        "required":["need"]}
        """
        private let catalogue: [ToolDefinition]
        private let revealed: Revealed

        /// - Parameters:
        ///   - catalogue: every tool the app has, described.
        ///   - revealed: the same value the extension was given.
        public init(catalogue: [ToolDefinition], revealed: Revealed) {
            self.catalogue = catalogue
            self.revealed = revealed
        }

        public func execute(
            _ call: ToolCall,
            delivering delivery: ResultDelivery
        ) async throws -> ToolOutcome {
            // A real app would match on the need. A template keeps the
            // matching obvious and leaves the cleverness to the app.
            let need = (try? JSONDecoder().decode(Need.self, from: Data(call.arguments.utf8)))?.need ?? ""
            let words = Set(need.lowercased().split(separator: " ").map(String.init))
            let found = catalogue.filter { tool in
                words.contains { tool.name.contains($0) || tool.description.lowercased().contains($0) }
            }
            await revealed.reveal(found.map(\.name))
            let listing = found.isEmpty
                ? "nothing else matches that"
                : found.map { "\($0.name): \($0.description)" }.joined(separator: "\n")
            return .result(ToolResult(callID: call.id, content: listing))
        }

        private struct Need: Decodable { let need: String }
    }
}
