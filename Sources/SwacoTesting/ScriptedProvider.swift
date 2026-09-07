import Swaco

/// A provider that plays a script: one list of stream events per turn, chosen
/// by how many assistant messages the context already holds. Never touches
/// the network. The replayable mock every test and example runs against.
public struct ScriptedProvider: Provider {
    public let turns: [[StreamEvent]]

    public init(turns: [[StreamEvent]]) {
        self.turns = turns
    }

    /// One turn that says `text` and stops.
    public static func saying(_ text: String) -> ScriptedProvider {
        ScriptedProvider(turns: [[.text(text), .stop(.endTurn)]])
    }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error> {
        let index = request.messages.filter { if case .assistant = $0 { true } else { false } }.count
        let script = index < turns.count ? turns[index] : [.stop(.endTurn)]
        return AsyncThrowingStream { continuation in
            for event in script { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// A provider that declares what a model can take, wrapping another. The way
/// to exercise a mismatch without needing the model that has it.
public struct DeclaringProvider: Provider {
    public let wrapped: any Provider
    public let capabilities: ModelCapabilities

    public init(_ wrapped: any Provider, capabilities: ModelCapabilities) {
        self.wrapped = wrapped
        self.capabilities = capabilities
    }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error> {
        wrapped.stream(request)
    }
}

public extension Provider {
    /// The same provider, declaring that it takes no tools.
    func withoutTools() -> DeclaringProvider {
        DeclaringProvider(self, capabilities: ModelCapabilities(tools: false))
    }
}
