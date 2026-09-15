import Foundation
import SwacoCore

/// Holds the tool calls the app's rule selects, and nothing more.
///
/// Swaco declares the facts a rule can be written over: what a tool said its
/// effect is, and where the event that started the run came from. Which calls
/// need approving, and how approving looks, are the app's. With no rule,
/// nothing is held: swaco ships no policy, not even a cautious one.
public struct ToolApproval: Extension {
    public let name = "approval"
    /// Given a call and what the tool declared, whether the person is asked.
    public typealias Rule = @Sendable (ToolCall, ToolEffect) -> Bool
    /// How the app asks. It may route this through `confirm`, or through
    /// anything else; swaco does not care, and does not import it.
    public typealias Approve = @Sendable (ToolCall) async -> Bool

    private let rule: Rule
    private let approve: Approve
    private let effect: @Sendable (String) -> ToolEffect?

    /// - Parameters:
    ///   - tools: the tools the agent was given, so a rule can read what each
    ///     one declared about itself.
    ///   - rule: which calls to hold. The default holds nothing.
    ///   - approve: how the person is asked.
    public init(
        tools: [any Tool],
        rule: @escaping Rule = { _, _ in false },
        approve: @escaping Approve
    ) {
        let declared = Dictionary(tools.map { ($0.name, $0.effect) }, uniquingKeysWith: { first, _ in first })
        self.effect = { declared[$0] }
        self.rule = rule
        self.approve = approve
    }

    /// A rule already written for the commonest case: hold anything that is
    /// not a mere observation.
    public static let anythingThatWrites: Rule = { _, effect in effect != .observation }

    public func beforeToolCall(
        _ call: ToolCall,
        in context: ExtensionContext
    ) async -> Decision<ToolCall> {
        guard let effect = effect(call.name) else { return .pass }
        guard rule(call, effect) else { return .pass }
        return await approve(call) ? .pass : .refuse("the person did not approve \(call.name)")
    }
}
