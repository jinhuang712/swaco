/// Results promised by deferred tools and not yet arrived. Actor-guarded so
/// delivery, awaiting and cancellation cannot race.
actor PendingResults {
    private var waiting: [String: CheckedContinuation<ToolResult?, Never>] = [:]
    private var arrived: [String: ToolResult] = [:]

    func deliver(_ result: ToolResult) {
        if let continuation = waiting.removeValue(forKey: result.callID) {
            continuation.resume(returning: result)
        } else {
            arrived[result.callID] = result
        }
    }

    /// Returns nil only if cancelled before the result arrived.
    func await(_ callID: String) async -> ToolResult? {
        if let early = arrived.removeValue(forKey: callID) { return early }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                register(callID, continuation)
            }
        } onCancel: {
            Task { await self.cancel(callID) }
        }
    }

    private func register(_ callID: String, _ continuation: CheckedContinuation<ToolResult?, Never>) {
        if Task.isCancelled {
            continuation.resume(returning: nil)
        } else {
            waiting[callID] = continuation
        }
    }

    private func cancel(_ callID: String) {
        waiting.removeValue(forKey: callID)?.resume(returning: nil)
    }
}
