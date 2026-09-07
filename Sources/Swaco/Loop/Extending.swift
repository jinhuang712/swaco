import Foundation

/// Applying an ordered list of extensions: strictly in order, rewrites
/// chained, any refusal winning. The loop asks for a decision and is told
/// what to do; who said so is recorded.
struct Extending: Sendable {
    let extensions: [any Extension]

    /// The result of asking every extension about one thing.
    enum Outcome<Subject: Sendable>: Sendable {
        case unchanged
        case rewritten(Subject, [Event])
        case refused(Event, reason: String)
    }

    func decide<Subject: Sendable>(
        _ subject: Subject,
        as what: @Sendable (Subject) -> Swaco.Subject,
        in context: ExtensionContext,
        hook: @Sendable (any Extension, Subject) async -> Decision<Subject>
    ) async -> Outcome<Subject> {
        var current = subject
        var changed = false
        var events: [Event] = []
        for extend in extensions {
            switch await hook(extend, current) {
            case .pass:
                continue
            case .rewrite(let next):
                current = next
                changed = true
                events.append(.rewritten(by: extend.name, subject: what(current)))
            case .refuse(let reason):
                return .refused(
                    .refused(by: extend.name, subject: what(current), reason: reason),
                    reason: reason
                )
            }
        }
        return changed ? .rewritten(current, events) : .unchanged
    }

    /// What to do with something that arrived. The first extension with an
    /// opinion decides; with none, it is not this loop's business.
    func arrival(
        of inbound: InboundEvent,
        in context: ExtensionContext
    ) async -> (Arrival, by: String) {
        for extend in extensions {
            if let arrival = await extend.arrived(inbound, in: context) {
                return (arrival, by: extend.name)
            }
        }
        return (.leave, by: "swaco")
    }

    /// Whether the loop may take another turn, and if not, what to record.
    func mayContinue(after turn: Int, in context: ExtensionContext) async -> Event? {
        for extend in extensions {
            switch await extend.turnEnded(turn, in: context) {
            case .pass:
                continue
            case .refuse(let reason):
                return .refused(by: extend.name, subject: .turn(turn), reason: reason)
            case .handOver(let reason):
                return .handedOver(by: extend.name, reason: reason)
            }
        }
        return nil
    }

    /// What to do about a failed request: the first extension that asks for a
    /// retry gets it.
    func recovery(from error: any Error, attempt: Int, in context: ExtensionContext) async -> Recovery {
        for extend in extensions {
            if case .retry(let delay) = await extend.requestFailed(error, attempt: attempt, in: context) {
                return .retry(after: delay)
            }
        }
        return .giveUp
    }

    func loopEnded(in context: ExtensionContext) async {
        for extend in extensions { await extend.loopEnded(in: context) }
    }
}
