/// Where an inbound event came from. A person typing is one source among
/// many, and none is assumed.
public enum Source: Sendable, Hashable {
    case person
    case shortcut
    case notification
    case url
    case share
    case system
    case schedule
    case sensor
}

/// Something that entered the agent: where it came from and what it carried.
/// The beginning of a run, recorded like everything else.
public struct InboundEvent: Sendable, Hashable {
    public let source: Source
    public let text: String

    public init(source: Source, text: String) {
        self.source = source
        self.text = text
    }

    /// What a person typed.
    public static func person(_ text: String) -> InboundEvent {
        InboundEvent(source: .person, text: text)
    }
}

/// Something the content asked for that the model had not declared.
public enum Capability: Sendable, Hashable {
    case tools
    case vision
    case reasoning
}

/// Why a loop stopped before the model did.
public enum CancellationOrigin: Sendable, Hashable {
    case person
    case system
}

/// Everything that leaves the agent, in the order it happened.
public enum Event: Sendable, Hashable {
    /// Something arrived. A log begins here, so it can be replayed alone.
    case arrived(InboundEvent)
    case turnStarted(Int)
    case text(String)
    case toolCallIssued(ToolCall)
    case toolCallDeferred(ToolCall)
    case toolResultArrived(ToolResult)
    case turnEnded(StopReason)
    case cancelled(CancellationOrigin, partial: String)
    case failed(String)
    /// The request asked for something this model has not declared. Recorded
    /// and nothing else: the loop does not refuse, the provider does not trim,
    /// the app decides.
    case capabilityMissing(Capability)
    case finished
    /// An event written by a swaco that knew a type this one does not. Kept
    /// exactly as it was written, and written back unchanged.
    case unrecognised(type: String, fields: [String: JSONValue])
}
