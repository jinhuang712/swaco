import Foundation
import Swaco

/// Runs a log again.
///
/// The promise behind saying the log format is public API: a bug report is a
/// log, and anyone holding one can reproduce the run without the vendor, the
/// key, the network, or the app it happened in. What the model said is in the
/// log, so a provider is built from it rather than asked again.
public struct ReplayingALog: Sendable {
    /// A provider that says what the model said in this log, turn by turn.
    ///
    /// The log records what arrived, not what was sent, which is the point:
    /// the loop is run again for real, and only the model is a recording.
    public static func provider(for events: [Event]) -> ScriptedProvider {
        var turns: [[StreamEvent]] = []
        var turn: [StreamEvent] = []
        var open = false

        for event in events {
            switch event {
            case .turnStarted:
                if open { turns.append(turn) }
                turn = []
                open = true
            case .text(let piece):
                turn.append(.text(piece))
            case .toolCallIssued(let call):
                turn.append(.toolCall(call))
            case .usage(let usage):
                turn.append(.usage(usage))
            case .turnEnded(let stop):
                turn.append(.stop(stop))
                turns.append(turn)
                turn = []
                open = false
            default:
                continue
            }
        }
        if open, !turn.isEmpty { turns.append(turn) }
        return ScriptedProvider(turns: turns)
    }

    /// What began the run this log recorded, so it can be started the same way.
    public static func arrival(in events: [Event]) -> InboundEvent? {
        for event in events {
            if case .arrived(let inbound) = event { return inbound }
        }
        return nil
    }

    /// What the tools answered, so a run can be replayed without them.
    ///
    /// The tools of a bug report are not to hand: they talked to a calendar
    /// somebody else owns, or to a person who has gone. What they said is in
    /// the log, so they are answered from it, and a tool whose answer is not
    /// there says so rather than pretending.
    public static func tools(in events: [Event]) -> [any Tool] {
        var answers: [String: [ToolResult]] = [:]
        var names: [String: String] = [:]
        for event in events {
            switch event {
            case .toolCallIssued(let call):
                names[call.id] = call.name
            case .toolResultArrived(let result):
                guard let name = names[result.callID] else { continue }
                answers[name, default: []].append(result)
            default:
                continue
            }
        }
        return answers.keys.sorted().map { name in
            RecordedTool(name: name, answers: answers[name] ?? [])
        }
    }
}

/// A tool that says what it said last time, in the order it said it.
struct RecordedTool: Tool {
    let name: String
    let description = "What this tool answered in the log being replayed"
    let access = ToolAccess.readOnly
    private let answers: Answers

    init(name: String, answers: [ToolResult]) {
        self.name = name
        self.answers = Answers(answers)
    }

    func execute(_ call: ToolCall, delivering delivery: ResultDelivery) async throws -> ToolOutcome {
        guard let said = await answers.next() else {
            return .result(ToolResult(
                callID: call.id,
                content: "the log has no further answer from \(name)",
                isError: true
            ))
        }
        // The id is this run's, not the recorded one's: a replay is a real
        // run, and its calls are its own.
        return .result(ToolResult(callID: call.id, content: said.content, isError: said.isError))
    }

    private actor Answers {
        private var remaining: [ToolResult]
        init(_ answers: [ToolResult]) { remaining = answers }
        func next() -> ToolResult? {
            remaining.isEmpty ? nil : remaining.removeFirst()
        }
    }
}
