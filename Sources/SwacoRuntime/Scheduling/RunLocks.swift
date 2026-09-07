import Foundation
import Swaco

/// Keeps two runs from writing to one log at the same time.
///
/// An app may run several agents at once, and it stays in control of them; what
/// it must never have to think about is two loops appending to one history in an
/// order neither chose. A run holds its group while it records and lets it go
/// when it has stopped, so a run that recovers a group waits for the one before
/// it to be finished with it, and reads a log nobody is still writing.
actor RunLocks {
    static let shared = RunLocks()

    private var held: Set<GroupID> = []
    private var waiting: [GroupID: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ group: GroupID) async {
        while held.contains(group) {
            await withCheckedContinuation { continuation in
                waiting[group, default: []].append(continuation)
            }
        }
        held.insert(group)
    }

    func release(_ group: GroupID) {
        held.remove(group)
        guard var queue = waiting[group], !queue.isEmpty else { return }
        let next = queue.removeFirst()
        waiting[group] = queue.isEmpty ? nil : queue
        next.resume()
    }
}
