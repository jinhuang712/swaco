import Foundation
import Swaco

/// A question put to a person.
public struct Question: Codable, Sendable, Hashable {
    public let question: String
    /// When present, the answer is expected to be one of these.
    public let options: [String]?

    public init(question: String, options: [String]? = nil) {
        self.question = question
        self.options = options
    }
}

/// An action a person is asked to approve. Also the shape used to ask for a
/// system authorisation.
public struct Confirmation: Codable, Sendable, Hashable {
    public let action: String
    public let detail: String?

    public init(action: String, detail: String? = nil) {
        self.action = action
        self.detail = detail
    }
}

/// Something the agent wants the person to know on the way, without waiting
/// and without ending its reply.
public struct Report: Codable, Sendable, Hashable {
    public let message: String

    public init(message: String) { self.message = message }
}

/// A request the agent has made and nobody has answered yet. After a
/// relaunch these are what an app puts back on screen.
public struct PendingRequest: Sendable, Hashable {
    public let callID: String
    public let request: Request

    public enum Request: Sendable, Hashable {
        case question(Question)
        case confirmation(Confirmation)
    }
}

/// The desk between the agent and the person.
///
/// Swaco owns the mechanics: the model sees the tools, a typed request appears
/// in the event stream, the loop waits for the result, and the wait survives
/// the process that started it, because a relaunched app hands the same desk
/// to the agent and the loop re-arms every call against it.
///
/// The app owns the presentation. Swaco has no opinion about how a question
/// looks, and none about what to do when nobody is there to answer it.
public actor Interaction {
    private var deliveries: [String: ResultDelivery] = [:]
    private var requests: [String: PendingRequest] = [:]
    private let reported: AsyncStream<Report>.Continuation

    /// Reports as they are made, for the app to show as it sees fit.
    public let reports: AsyncStream<Report>

    public init() {
        (reports, reported) = AsyncStream<Report>.makeStream()
    }

    /// The tools to hand to an agent. A single tool is a toolset of one, and
    /// an app that wants only some of them names only those. Reachable from
    /// anywhere: building the tools touches nothing the desk is guarding.
    public nonisolated var tools: [any Tool] { [Ask(self), Confirm(self), Tell(self)] }

    /// Requests waiting for an answer, in the order they were made.
    public var pending: [PendingRequest] {
        requests.values.sorted { $0.callID < $1.callID }
    }

    /// Answers a question. Unknown or already answered calls are ignored, so a
    /// screen shown twice cannot answer twice.
    public func answer(_ callID: String, with text: String) async {
        await finish(callID, content: text)
    }

    /// Approves or refuses an action.
    public func decide(_ callID: String, granted: Bool) async {
        await finish(callID, content: granted ? "granted" : "refused")
    }

    private func finish(_ callID: String, content: String) async {
        guard let delivery = deliveries.removeValue(forKey: callID) else { return }
        requests[callID] = nil
        await delivery(ToolResult(callID: callID, content: content))
    }

    fileprivate func register(_ request: PendingRequest, delivering delivery: ResultDelivery) {
        requests[request.callID] = request
        deliveries[request.callID] = delivery
    }

    fileprivate func report(_ report: Report) {
        reported.yield(report)
    }
}

/// Put a question to the person, free-form or with options.
struct Ask: Tool {
    let name = "ask"
    let description = "Ask the person a question and wait for their answer"
    let access = ToolAccess.readOnly
    let parameters = """
    {"type":"object","properties":{\
    "question":{"type":"string","description":"What to ask"},\
    "options":{"type":"array","items":{"type":"string"},"description":"The answers to choose from, if any"}},\
    "required":["question"]}
    """
    private let desk: Interaction

    init(_ desk: Interaction) { self.desk = desk }

    func execute(_ call: ToolCall, delivering delivery: ResultDelivery) async throws -> ToolOutcome {
        try await register(call, delivering: delivery)
        return .deferred
    }

    /// A fresh process: register the same request again, so the app finds it
    /// waiting and the answer reaches this loop.
    func resume(_ call: ToolCall, delivering delivery: ResultDelivery) async throws {
        try await register(call, delivering: delivery)
    }

    private func register(_ call: ToolCall, delivering delivery: ResultDelivery) async throws {
        let question = try JSONDecoder().decode(Question.self, from: Data(call.arguments.utf8))
        await desk.register(
            PendingRequest(callID: call.id, request: .question(question)),
            delivering: delivery
        )
    }
}

/// Have the person approve or refuse an action.
struct Confirm: Tool {
    let name = "confirm"
    let description = "Ask the person to approve an action before it is taken"
    let access = ToolAccess.readOnly
    let parameters = """
    {"type":"object","properties":{\
    "action":{"type":"string","description":"What is about to happen"},\
    "detail":{"type":"string","description":"Anything the person should know first"}},\
    "required":["action"]}
    """
    private let desk: Interaction

    init(_ desk: Interaction) { self.desk = desk }

    func execute(_ call: ToolCall, delivering delivery: ResultDelivery) async throws -> ToolOutcome {
        try await register(call, delivering: delivery)
        return .deferred
    }

    func resume(_ call: ToolCall, delivering delivery: ResultDelivery) async throws {
        try await register(call, delivering: delivery)
    }

    private func register(_ call: ToolCall, delivering delivery: ResultDelivery) async throws {
        let confirmation = try JSONDecoder().decode(Confirmation.self, from: Data(call.arguments.utf8))
        await desk.register(
            PendingRequest(callID: call.id, request: .confirmation(confirmation)),
            delivering: delivery
        )
    }
}

/// Tell the person something on the way. Waits for nobody.
struct Tell: Tool {
    let name = "report"
    let description = "Tell the person about progress without waiting for a reply"
    let access = ToolAccess.readOnly
    let parameters = """
    {"type":"object","properties":{\
    "message":{"type":"string","description":"What to tell the person"}},\
    "required":["message"]}
    """
    private let desk: Interaction

    init(_ desk: Interaction) { self.desk = desk }

    func execute(_ call: ToolCall, delivering delivery: ResultDelivery) async throws -> ToolOutcome {
        let report = try JSONDecoder().decode(Report.self, from: Data(call.arguments.utf8))
        await desk.report(report)
        return .result(ToolResult(callID: call.id, content: "told"))
    }
}
