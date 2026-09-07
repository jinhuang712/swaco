import Foundation
import Observation
import Swaco
import SwacoFoundationModels
import SwacoInteraction
import SwacoOpenAI
import SwacoRuntime
import SwacoTesting

/// Everything this app needs to be agentic, in one place.
///
/// Adoption is four things: a store, a desk, an agent, and a session. Nothing
/// is initialised, registered or configured beyond naming what this app uses.
@MainActor @Observable
final class Chat {
    /// What the screen shows.
    private(set) var turns: [Turn] = []
    private(set) var waiting: PendingRequest?
    private(set) var running = false
    private(set) var notice: String?

    /// The person's choice of model, which swaco has no opinion about.
    var useOnDeviceModel = false
    var hostedKey = UserDefaults.standard.string(forKey: "hosted-key") ?? "" {
        didSet { UserDefaults.standard.set(hostedKey, forKey: "hosted-key") }
    }

    private let store: any EventStore
    private let desk = Interaction()
    private let session: Session
    private var streaming = ""

    init() {
        // One log, in this app's own container. An app extension would reach
        // the same one through an App Group.
        let directory = URL.documentsDirectory.appending(path: "swaco")
        // A test that drives this screen says where to start from.
        if ProcessInfo.processInfo.arguments.contains("-forget-everything") {
            try? FileManager.default.removeItem(at: directory)
        }
        store = try! FileEventStore(directory: directory)
        session = Session(id: GroupID("the-conversation"), store: store)
    }

    /// On launch: show what was said before, and if the agent was waiting on
    /// an answer when the app went away, put the question back and re-arm the
    /// loop that asked it.
    func begin() async {
        await show(history: (try? await session.history()) ?? [])
        await watchReports()

        guard case .awaitingResults = (try? await session.state()) else { return }
        notice = "Picking up where we left off."
        await consume { session.run(with: agent()).resume() }
    }

    func send(_ text: String) async {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty, !running else { return }
        await consume { session.run(with: agent()).start(said) }
    }

    func answer(_ text: String) async {
        guard let waiting else { return }
        self.waiting = nil
        await desk.answer(waiting.callID, with: text)
    }

    func decide(granted: Bool) async {
        guard let waiting else { return }
        self.waiting = nil
        await desk.decide(waiting.callID, granted: granted)
    }

    // MARK: - Putting swaco to work

    private func agent() -> Agent {
        Agent(provider: provider(), tools: desk.tools)
    }

    private func provider() -> any Provider {
        // A conversation this app once had with a real model, kept in the
        // bundle. It is how the app runs with no key and no network: in a
        // preview, in a demo, and in the tests that drive this screen.
        if Self.replaying,
           let file = Bundle.main.url(forResource: "asking", withExtension: "jsonl"),
           let recorded = try? ScriptedProvider.replaying(file) {
            return recorded
        }
        if useOnDeviceModel { return OnDeviceModel(instructions: Self.instructions) }
        return OpenAI.compatible(
            model: "muse-spark-1.3-contributor",
            endpoint: "https://opencode.ai/zen/go/v1/responses",
            authentication: .bearer(hostedKey),
            headers: ["x-opencode-session": "swaco-chat-app"]
        )
    }

    /// Set by a launch argument, so a test or a demo says so from outside
    /// rather than the app deciding for itself.
    static let replaying = ProcessInfo.processInfo.arguments.contains("-recorded")

    private static let instructions = """
        You are a helpful assistant inside a small iOS app. Keep replies short. \
        When something is genuinely ambiguous, ask the person with the ask tool \
        rather than guessing.
        """

    private func consume(_ start: () -> AsyncThrowingStream<Event, any Error>) async {
        running = true
        streaming = ""
        defer { running = false }
        do {
            for try await event in start() { await apply(event) }
        } catch {
            notice = String(describing: error)
        }
    }

    private func apply(_ event: Event) async {
        switch event {
        case .arrived(let inbound):
            turns.append(Turn(who: .person, text: inbound.text))
        case .text(let piece):
            streaming += piece
            if case .agent = turns.last?.who {
                turns[turns.count - 1].text = streaming
            } else {
                turns.append(Turn(who: .agent, text: streaming))
            }
        case .turnEnded:
            streaming = ""
        case .toolCallDeferred:
            // The agent is waiting on the person. What that looks like is
            // this app's decision; that the loop waits is swaco's.
            waiting = await desk.pending.first
        case .toolResultArrived(let result):
            if waiting?.callID == result.callID { waiting = nil }
        case .capabilityMissing(.tools):
            notice = "This model runs no tools, so it cannot ask you anything."
        case .failed(let message):
            notice = message
        case .handedOver:
            notice = "Picking this up again in a moment."
        case .cancelled, .capabilityMissing, .turnStarted, .toolCallIssued, .finished,
             .rewritten, .refused, .arrivalHandled, .usage, .unrecognised:
            break
        }
    }

    private func show(history: [Event]) async {
        turns = Message.projection(of: history).compactMap { message in
            switch message {
            case .user: Turn(who: .person, text: message.text)
            case .assistant where !message.text.isEmpty: Turn(who: .agent, text: message.text)
            default: nil
            }
        }
    }

    private func watchReports() async {
        Task { [desk] in
            for await report in await desk.reports {
                await MainActor.run { turns.append(Turn(who: .agent, text: report.message)) }
            }
        }
    }

    struct Turn: Identifiable {
        let id = UUID()
        let who: Who
        var text: String
        enum Who { case person, agent }
    }
}
