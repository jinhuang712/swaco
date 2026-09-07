import Foundation
import os
import Swaco

/// Makes a run visible in Instruments: an interval per turn and per tool call.
///
/// It is an extension, which is the point: the moments worth measuring are
/// exactly the moments the loop already offers, so this needs no privileged
/// access and is written the way any third party would write it. An app that
/// wants it lists it; an app that does not pays nothing.
///
/// As with the log, structure is measured and content is never recorded.
public struct Trace: Extension {
    public let name = "trace"
    private let intervals = Intervals()

    public init() {}

    public func beforeRequest(
        _ request: ModelRequest,
        in context: ExtensionContext
    ) async -> Decision<ModelRequest> {
        await intervals.begin("turn", named: "turn \(context.turn)")
        Log.run.debug("turn \(context.turn, privacy: .public) requested")
        return .pass
    }

    public func beforeToolCall(
        _ call: ToolCall,
        in context: ExtensionContext
    ) async -> Decision<ToolCall> {
        await intervals.begin(call.id, named: "tool \(call.name)")
        return .pass
    }

    public func afterToolCall(
        _ result: ToolResult,
        in context: ExtensionContext
    ) async -> Decision<ToolResult> {
        await intervals.end(result.callID)
        return .pass
    }

    public func turnEnded(_ turn: Int, in context: ExtensionContext) async -> Verdict {
        await intervals.end("turn")
        return .pass
    }

    public func loopEnded(in context: ExtensionContext) async {
        await intervals.endAll()
    }

    /// Signpost intervals in flight. An actor because a turn and several tool
    /// calls may be open at once and the ends must find their beginnings.
    private actor Intervals {
        private var open: [String: OSSignpostIntervalState] = [:]

        func begin(_ key: String, named name: String) {
            guard open[key] == nil else { return }
            open[key] = Log.signposts.beginInterval("swaco", id: Log.signposts.makeSignpostID(),
                                                   "\(name, privacy: .public)")
        }

        func end(_ key: String) {
            guard let state = open.removeValue(forKey: key) else { return }
            Log.signposts.endInterval("swaco", state)
        }

        func endAll() {
            for state in open.values { Log.signposts.endInterval("swaco", state) }
            open = [:]
        }
    }
}
