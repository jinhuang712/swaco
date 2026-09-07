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
    /// Applied strictly in this order, rewrites chained, any refusal winning.
    public let extensions: [any Extension]
    /// How an inbound event becomes model input. Replaceable whole.
    public let rendering: any EventRendering
    /// Where the loop is running, as whatever runs it knows.
    public let execution: ExecutionContext

    public init(
        provider: any Provider,
        tools: [any Tool],
        extensions: [any Extension] = [],
        rendering: any EventRendering = DefaultEventRendering(),
        execution: ExecutionContext = .unknown
    ) {
        self.provider = provider
        self.tools = tools
        self.extensions = extensions
        self.rendering = rendering
        self.execution = execution
    }

    /// The same agent with a different sense of where it is running. What
    /// runs the loop knows this; the agent it was handed did not.
    public func running(in execution: ExecutionContext) -> Agent {
        Agent(provider: provider, tools: tools, extensions: extensions,
              rendering: rendering, execution: execution)
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

        if !definitions.isEmpty, !provider.capabilities.tools {
            emit(.capabilityMissing(.tools))
        }

        let extending = Extending(extensions: extensions)

        while true {
            turn += 1
            let moment = ExtensionContext(turn: turn, execution: execution)
            emit(.turnStarted(turn))

            var request = ModelRequest(messages: messages, tools: definitions)
            switch await extending.decide(request, as: { _ in .request }, in: moment,
                                          hook: { await $0.beforeRequest($1, in: moment) }) {
            case .unchanged:
                break
            case .rewritten(let rewritten, let events):
                events.forEach(emit)
                request = rewritten
            case .refused(let event, _):
                emit(event)
                await extending.loopEnded(in: moment)
                return
            }

            var text = ""
            var calls: [ToolCall] = []
            var stop: StopReason = .endTurn
            var attempt = 0

            streaming: while true {
                attempt += 1
                text = ""
                calls = []
                do {
                    for try await event in provider.stream(request) {
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
                    break streaming
                } catch {
                    // A failed request is the one thing an extension may ask
                    // to have another go at.
                    switch await extending.recovery(from: error, attempt: attempt, in: moment) {
                    case .giveUp:
                        emit(.failed(String(describing: error)))
                        await extending.loopEnded(in: moment)
                        return
                    case .retry(let delay):
                        try? await Task.sleep(for: delay)
                        if Task.isCancelled {
                            emit(.cancelled(flag.isPerson ? .person : .system, partial: text))
                            await extending.loopEnded(in: moment)
                            return
                        }
                        continue streaming
                    }
                }
            }

            if Task.isCancelled {
                emit(.cancelled(flag.isPerson ? .person : .system, partial: text))
                await extending.loopEnded(in: moment)
                return
            }

            var response = Response(text: text, toolCalls: calls, stop: stop)
            switch await extending.decide(response, as: { _ in .response }, in: moment,
                                          hook: { await $0.afterResponse($1, in: moment) }) {
            case .unchanged:
                break
            case .rewritten(let rewritten, let events):
                events.forEach(emit)
                response = rewritten
            case .refused(let event, _):
                emit(event)
                await extending.loopEnded(in: moment)
                return
            }

            messages.append(.assistant(text: response.text, toolCalls: response.toolCalls))
            emit(.turnEnded(response.stop))

            if response.toolCalls.isEmpty || response.stop != .toolUse {
                if let refusal = await extending.mayContinue(after: turn, in: moment) { emit(refusal) }
                emit(.finished)
                await extending.loopEnded(in: moment)
                return
            }

            for issued in response.toolCalls {
                var call = issued
                switch await extending.decide(call, as: { .toolCall($0.id) }, in: moment,
                                              hook: { await $0.beforeToolCall($1, in: moment) }) {
                case .unchanged:
                    break
                case .rewritten(let rewritten, let events):
                    events.forEach(emit)
                    call = rewritten
                case .refused(let event, let reason):
                    // The call still gets a result, so the model is told it
                    // was refused rather than left waiting.
                    emit(event)
                    let refused = ToolResult(callID: call.id, content: reason, isError: true)
                    emit(.toolResultArrived(refused))
                    messages.append(.toolResult(refused))
                    continue
                }

                let produced: ToolResult?
                do {
                    produced = try await execute(call, delivery: delivery, pending: pending, emit: emit)
                } catch {
                    produced = ToolResult(callID: call.id, content: String(describing: error), isError: true)
                }
                guard var result = produced else {
                    emit(.cancelled(flag.isPerson ? .person : .system, partial: text))
                    await extending.loopEnded(in: moment)
                    return
                }

                switch await extending.decide(result, as: { .toolResult($0.callID) }, in: moment,
                                              hook: { await $0.afterToolCall($1, in: moment) }) {
                case .unchanged:
                    break
                case .rewritten(let rewritten, let events):
                    events.forEach(emit)
                    result = rewritten
                case .refused(let event, let reason):
                    emit(event)
                    result = ToolResult(callID: result.callID, content: reason, isError: true)
                }

                emit(.toolResultArrived(result))
                messages.append(.toolResult(result))
            }

            if let refusal = await extending.mayContinue(after: turn, in: moment) {
                emit(refusal)
                await extending.loopEnded(in: moment)
                return
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
