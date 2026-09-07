import Foundation
import FoundationModels
import Swaco

/// Apple's on-device model, as one provider among others.
///
/// It is no more and no less favoured than a hosted one: the same protocol, the
/// same vocabulary, the same events. What differs is what it has declared. This
/// model runs tools itself rather than handing calls back, and swaco's loop
/// owns tool execution, so the provider declares no tool support: a request
/// that carries tools is recorded as a mismatch and the app decides.
public struct OnDeviceModel: Provider {
    /// Standing instructions, given to the model ahead of the conversation.
    public let instructions: String?

    public init(instructions: String? = nil) {
        self.instructions = instructions
    }

    public var capabilities: ModelCapabilities {
        ModelCapabilities(tools: false, vision: false, reasoning: false, providerExecutedTools: false)
    }

    /// Asked before the first request, not discovered after the first failure.
    public var availability: ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.modelNotReady):
            return .downloading
        case .unavailable(.deviceNotEligible):
            return .unavailable("this device cannot run the on-device model")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence is not turned on")
        case .unavailable(let reason):
            return .unavailable(String(describing: reason))
        }
    }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard case .ready = availability else {
                        throw OnDeviceError.unavailable(availability)
                    }
                    let (history, latest) = Self.divide(request.messages)
                    let session = LanguageModelSession(
                        model: .default,
                        tools: [],
                        transcript: Self.transcript(of: history, instructions: instructions)
                    )

                    // Snapshots are cumulative; swaco's events are what is new.
                    var sent = ""
                    for try await snapshot in session.streamResponse(to: latest) {
                        let whole = snapshot.content
                        guard whole.count > sent.count else { continue }
                        continuation.yield(.text(String(whole.dropFirst(sent.count))))
                        sent = whole
                    }
                    continuation.yield(.stop(.endTurn))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Everything but the last thing said, which becomes the prompt.
    private static func divide(_ messages: [Message]) -> ([Message], String) {
        guard let last = messages.last else { return ([], "") }
        if case .user(let text) = last {
            return (messages.dropLast(), text)
        }
        return (messages, "")
    }

    private static func transcript(of messages: [Message], instructions: String?) -> Transcript {
        var entries: [Transcript.Entry] = []
        if let instructions {
            entries.append(.instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: instructions))],
                toolDefinitions: []
            )))
        }
        for message in messages {
            switch message {
            case .system(let text):
                entries.append(.instructions(Transcript.Instructions(
                    segments: [.text(Transcript.TextSegment(content: text))],
                    toolDefinitions: []
                )))
            case .user(let text):
                entries.append(.prompt(Transcript.Prompt(
                    segments: [.text(Transcript.TextSegment(content: text))]
                )))
            case .assistant(let text, _) where !text.isEmpty:
                entries.append(.response(Transcript.Response(
                    assetIDs: [],
                    segments: [.text(Transcript.TextSegment(content: text))]
                )))
            case .toolResult(let result):
                // This model was not given the tool, so a result reaches it as
                // something that was said rather than as a call it made.
                entries.append(.prompt(Transcript.Prompt(
                    segments: [.text(Transcript.TextSegment(content: result.content))]
                )))
            case .assistant:
                continue
            }
        }
        return Transcript(entries: entries)
    }
}

public enum OnDeviceError: Error, Sendable {
    case unavailable(ModelAvailability)
}
