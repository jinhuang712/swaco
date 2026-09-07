import Synchronization
/// A running loop: its events, and a way to stop it from outside.
public struct AgentRun: Sendable {
    public let events: AsyncStream<Event>
    private let task: Task<Void, Never>
    private let origin: CancellationFlag

    init(events: AsyncStream<Event>, task: Task<Void, Never>, origin: CancellationFlag) {
        self.events = events
        self.task = task
        self.origin = origin
    }

    /// Stop the loop because a person asked. Cancelling the consuming task
    /// instead records the origin as the system.
    public func cancel() {
        origin.markPerson()
        task.cancel()
    }
}

/// Set once when a person cancels; read when the loop winds down.
final class CancellationFlag: Sendable {
    private let state: Mutex<Bool>
    init() { state = Mutex(false) }
    func markPerson() { state.withLock { $0 = true } }
    var isPerson: Bool { state.withLock { $0 } }
}

/// The loop, configured and callable. Context in, events out; request,
/// stream, execute tool calls, repeat until the model stops.
public struct Agent: Sendable {
    public let provider: any Provider
    public let tools: [any Tool]
    /// How an inbound event becomes model input. Replaceable whole.
    public let rendering: any EventRendering

    public init(
        provider: any Provider,
        tools: [any Tool],
        rendering: any EventRendering = DefaultEventRendering()
    ) {
        self.provider = provider
        self.tools = tools
        self.rendering = rendering
    }

    /// Starts a loop from something that arrived.
    public func run(_ inbound: InboundEvent) -> AgentRun {
        run(from: .beginning(inbound, rendering: rendering))
    }

    /// Starts a loop from what a person typed.
    public func run(_ text: String) -> AgentRun {
        run(.person(text))
    }

    /// Continues a loop whose events already exist: the context is what the
    /// log projects, and every call left without a result is handed back to
    /// its tool before the next turn.
    public func run(from context: Context) -> AgentRun {
        let (events, continuation) = AsyncStream<Event>.makeStream()
        let flag = CancellationFlag()
        let pending = PendingResults()
        let task = Task {
            await loop(context: context, pending: pending, flag: flag, emit: { continuation.yield($0) })
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return AgentRun(events: events, task: task, origin: flag)
    }

    private func loop(
        context: Context,
        pending: PendingResults,
        flag: CancellationFlag,
        emit: @Sendable (Event) -> Void
    ) async {
        var messages = context.messages
        if let arrival = context.arrival { emit(.arrived(arrival)) }
        let definitions = tools.map { ToolDefinition(name: $0.name, description: $0.description, parameters: $0.parameters) }
        let delivery = ResultDelivery { result in await pending.deliver(result) }
        var turn = context.turnsSoFar

        // A wait that outlived the process it started in: hand each call back
        // to its tool, and only then take another turn.
        for call in context.waiting {
            guard let tool = tools.first(where: { $0.name == call.name }) else {
                let lost = ToolResult(callID: call.id, content: "no tool named \(call.name)", isError: true)
                emit(.toolResultArrived(lost))
                messages.append(.toolResult(lost))
                continue
            }
            do {
                try await tool.resume(call, delivering: delivery)
            } catch {
                let failure = ToolResult(callID: call.id, content: String(describing: error), isError: true)
                emit(.toolResultArrived(failure))
                messages.append(.toolResult(failure))
                continue
            }
            emit(.toolCallDeferred(call))
            guard let result = await pending.await(call.id) else {
                emit(.cancelled(flag.isPerson ? .person : .system, partial: ""))
                return
            }
            emit(.toolResultArrived(result))
            messages.append(.toolResult(result))
        }

        while true {
            turn += 1
            emit(.turnStarted(turn))
            var text = ""
            var calls: [ToolCall] = []
            var stop: StopReason = .endTurn

            do {
                for try await event in provider.stream(ModelRequest(messages: messages, tools: definitions)) {
                    if Task.isCancelled { break }
                    switch event {
                    case .text(let piece):
                        text += piece
                        emit(.text(piece))
                    case .toolCall(let call):
                        calls.append(call)
                        emit(.toolCallIssued(call))
                    case .stop(let reason):
                        stop = reason
                    }
                }
            } catch {
                emit(.failed(String(describing: error)))
                return
            }

            if Task.isCancelled {
                emit(.cancelled(flag.isPerson ? .person : .system, partial: text))
                return
            }

            messages.append(.assistant(text: text, toolCalls: calls))
            emit(.turnEnded(stop))

            if calls.isEmpty || stop != .toolUse {
                emit(.finished)
                return
            }

            for call in calls {
                let result: ToolResult?
                do {
                    result = try await execute(call, delivery: delivery, pending: pending, emit: emit)
                } catch {
                    result = ToolResult(callID: call.id, content: String(describing: error), isError: true)
                }
                guard let result else {
                    emit(.cancelled(flag.isPerson ? .person : .system, partial: text))
                    return
                }
                emit(.toolResultArrived(result))
                messages.append(.toolResult(result))
            }
        }
    }

    /// Nil means cancelled while waiting for a deferred result.
    private func execute(
        _ call: ToolCall,
        delivery: ResultDelivery,
        pending: PendingResults,
        emit: @Sendable (Event) -> Void
    ) async throws -> ToolResult? {
        guard let tool = tools.first(where: { $0.name == call.name }) else {
            return ToolResult(callID: call.id, content: "no tool named \(call.name)", isError: true)
        }
        switch try await tool.execute(call, delivering: delivery) {
        case .result(let result):
            return result
        case .deferred:
            emit(.toolCallDeferred(call))
            return await pending.await(call.id)
        }
    }
}
