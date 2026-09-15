/// Something that entered the agent: where it came from and what it carried.
/// The beginning of a run, recorded like everything else.
///
/// The source is an opaque identifier, not a closed set: a person typing is
/// one source among many, and the vocabulary of sources lives above the core
/// (platform layers provide the well-known ones, apps define their own).
/// The core carries the identifier so the model and extensions can tell what
/// a person said from what the system delivered, without knowing the list.
public struct InboundEvent: Sendable, Hashable {
    public let source: String
    /// What arrived: words, pictures, or anything else a part can hold.
    public let content: [ContentPart]

    public init(source: String, content: [ContentPart]) {
        self.source = source
        self.content = content
    }

    public init(source: String, text: String) {
        self.init(source: source, content: [.text(text)])
    }

    /// The words that arrived. A share sheet may bring none.
    public var text: String { content.text }

    /// What a person typed.
    public static func person(_ text: String) -> InboundEvent {
        InboundEvent(source: "person", text: text)
    }
}

/// Something the content asked for that the model had not declared.
/// `vision` keeps its name so logs written before audio and video existed
/// still read.
public enum Capability: Sendable, Hashable {
    case tools
    case vision
    case audio
    case video
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
    /// What the turn cost, as the vendor counted it.
    case usage(Usage)
    case turnEnded(StopReason)
    case cancelled(CancellationOrigin, partial: String)
    case failed(String)
    /// What was done with something that arrived while the loop was running,
    /// and who decided.
    case arrivalHandled(Arrival, by: String)
    /// The loop stopped on purpose and expects another process to go on from
    /// here. Not an ending: the work is unfinished and says so.
    case handedOver(by: String, reason: String)
    /// An extension changed something on its way through the loop.
    case rewritten(by: String, subject: Subject)
    /// An extension refused something. What that ends depends on where it
    /// happened, and the log says where.
    case refused(by: String, subject: Subject, reason: String)
    /// The request asked for something this model has not declared. Recorded
    /// and nothing else: the loop does not refuse, the provider does not trim,
    /// the app decides.
    case capabilityMissing(Capability)
    case finished
    /// An event written by a swaco that knew a type this one does not. Kept
    /// exactly as it was written, and written back unchanged.
    case unrecognised(type: String, fields: [String: JSONValue])
}

public extension Event {
    /// The name of what happened, and nothing about what it said.
    /// The name of what happened, carrying nothing of what it said.
    ///
    /// This is what may be written to a system log, sent in a bug report, or
    /// shown in a trace: that a turn started, that a tool was called, that a
    /// call was refused. Never what a person said, what the model replied, or
    /// what a tool returned. A log that can be left on is one that carries
    /// nobody's words.
    var kind: String {
        switch self {
        case .arrived(let inbound): "arrived(\(inbound.source))"
        case .turnStarted(let turn): "turn \(turn) started"
        case .text: "text"
        case .toolCallIssued(let call): "call issued(\(call.name))"
        case .toolCallDeferred(let call): "call deferred(\(call.name))"
        case .toolResultArrived(let result): result.isError ? "result arrived(error)" : "result arrived"
        case .usage: "usage"
        case .turnEnded(let stop): "turn ended(\(stop))"
        case .cancelled(let origin, _): "cancelled(\(origin))"
        case .failed: "failed"
        case .capabilityMissing(let capability): "capability missing(\(capability))"
        case .rewritten(let by, _): "rewritten(\(by))"
        case .refused(let by, _, _): "refused(\(by))"
        case .handedOver(let by, _): "handed over(\(by))"
        case .arrivalHandled(let arrival, let by): "arrival \(arrival)(\(by))"
        case .finished: "finished"
        case .unrecognised(let type, _): "unrecognised(\(type))"
        }
    }
}
