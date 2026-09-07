import Foundation

/// What an extension decides about something passing through the loop: leave
/// it alone, change it, or refuse it.
public enum Decision<Subject: Sendable>: Sendable {
    case pass
    case rewrite(Subject)
    case refuse(String)
}

/// What an extension decides where there is nothing to rewrite.
public enum Verdict: Sendable, Hashable {
    case pass
    /// Stop, and do not expect to go on.
    case refuse(String)
    /// Stop, and expect another process to go on from here.
    ///
    /// The difference from a refusal is what it means afterwards: a refused
    /// loop is over, a handed-over loop is waiting for its next process. An
    /// app extension with three seconds left, a background wake-up that must
    /// give the system its time back: both stop like this, and both are
    /// picked up by whatever runs next.
    case handOver(String)
}

/// What to do about a request that failed.
public enum Recovery: Sendable, Hashable {
    case giveUp
    case retry(after: Duration)
}

/// One turn as the model produced it, before the loop acts on it.
public struct Response: Sendable, Hashable {
    /// What the model said, in parts.
    public var content: [ContentPart]
    /// What it asked to have done.
    public var toolCalls: [ToolCall]
    /// Why it stopped.
    public var stop: StopReason
    /// What this turn cost, where the vendor said.
    public var usage: Usage?

    public init(
        content: [ContentPart],
        toolCalls: [ToolCall],
        stop: StopReason,
        usage: Usage? = nil
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.stop = stop
        self.usage = usage
    }

    public init(text: String, toolCalls: [ToolCall], stop: StopReason) {
        self.init(content: text.isEmpty ? [] : [.text(text)], toolCalls: toolCalls, stop: stop)
    }

    /// The words the model said.
    public var text: String { content.text }
}

/// Where the loop is running and what it can count on. Filled in by whatever
/// runs the loop; the core carries it so an extension can read it.
public struct ExecutionContext: Sendable, Hashable, Codable {
    public enum Placement: String, Sendable, Hashable, Codable {
        case foreground
        case background
        /// A separate process: a share sheet, a widget, an intent.
        case appExtension
    }

    /// Where this process is: in front of someone, behind, or beside.
    public var placement: Placement
    /// How long this process can expect to keep running, where the system says.
    public var remainingTime: TimeInterval?
    /// Whether anyone is there to answer. A run woken by a schedule has nobody.
    public var personIsPresent: Bool

    public init(
        placement: Placement = .foreground,
        remainingTime: TimeInterval? = nil,
        personIsPresent: Bool = true
    ) {
        self.placement = placement
        self.remainingTime = remainingTime
        self.personIsPresent = personIsPresent
    }

    /// What a program that has not said knows: it is running, and it does not
    /// claim to know more.
    public static let unknown = ExecutionContext()
}

/// What an extension is told about the moment it is acting in.
public struct ExtensionContext: Sendable {
    public let turn: Int
    public let execution: ExecutionContext
    /// Whether the loop is waiting on a result that will arrive later. The
    /// fact an intake rule most wants: something arriving while the agent is
    /// waiting on a person is not the same as one arriving mid-thought.
    public let waitingForResult: Bool

    public init(turn: Int, execution: ExecutionContext, waitingForResult: Bool = false) {
        self.turn = turn
        self.execution = execution
        self.waitingForResult = waitingForResult
    }
}

/// A value that acts at one or more moments of the loop.
///
/// The hooks are exactly those moments and no others. Each may pass, rewrite
/// or refuse. The app declares extensions as an ordered list; swaco applies
/// them strictly in that order, chains rewrites so each sees what the one
/// before it produced, and lets any refusal win.
///
/// Every hook has a default that passes, so an extension writes only the
/// moment it cares about, and a new hook never breaks one already written.
public protocol Extension: Sendable {
    /// A name for the log, so a rewrite or a refusal says who did it.
    var name: String { get }

    /// Something arrived while the loop was running. Nil is no opinion; with
    /// no opinion from anyone the event is left, which is how an app that
    /// lists no intake extension gets a new run for every arrival.
    func arrived(_ inbound: InboundEvent, in context: ExtensionContext) async -> Arrival?
    func beforeRequest(_ request: ModelRequest, in context: ExtensionContext) async -> Decision<ModelRequest>
    func afterResponse(_ response: Response, in context: ExtensionContext) async -> Decision<Response>
    /// A refusal here becomes the call's result, marked as an error, so the
    /// model learns it was refused and the loop keeps its promise that every
    /// call has a result.
    func beforeToolCall(_ call: ToolCall, in context: ExtensionContext) async -> Decision<ToolCall>
    func afterToolCall(_ result: ToolResult, in context: ExtensionContext) async -> Decision<ToolResult>
    /// A refusal here ends the loop, which is how a budget stops one; a
    /// handover stops it for now, which is how a process gives its time back
    /// without losing the work.
    func turnEnded(_ turn: Int, in context: ExtensionContext) async -> Verdict
    /// The first extension that asks for a retry gets it.
    func requestFailed(_ error: any Error, attempt: Int, in context: ExtensionContext) async -> Recovery
    func loopEnded(in context: ExtensionContext) async
}

public extension Extension {
    func arrived(_ inbound: InboundEvent, in context: ExtensionContext) async -> Arrival? { nil }
    func beforeRequest(_ request: ModelRequest, in context: ExtensionContext) async -> Decision<ModelRequest> { .pass }
    func afterResponse(_ response: Response, in context: ExtensionContext) async -> Decision<Response> { .pass }
    func beforeToolCall(_ call: ToolCall, in context: ExtensionContext) async -> Decision<ToolCall> { .pass }
    func afterToolCall(_ result: ToolResult, in context: ExtensionContext) async -> Decision<ToolResult> { .pass }
    func turnEnded(_ turn: Int, in context: ExtensionContext) async -> Verdict { .pass }
    func requestFailed(_ error: any Error, attempt: Int, in context: ExtensionContext) async -> Recovery { .giveUp }
    func loopEnded(in context: ExtensionContext) async {}
}

/// What an extension acted on, for the log.
public enum Subject: Sendable, Hashable {
    case request
    case response
    case toolCall(String)
    case toolResult(String)
    case turn(Int)
}
