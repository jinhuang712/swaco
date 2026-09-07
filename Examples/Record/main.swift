import Foundation
import Swaco
import SwacoExtensions
import SwacoOpenAI
import SwacoTesting

/// Runs the first program's exchange once against a real model and keeps it.
///
/// This is the workflow the feature list promises: ask a vendor once, keep
/// what it said, and let development, previews and tests do without a key and
/// a network from then on. Run it by hand when a recording needs refreshing;
/// nothing in CI runs it, because CI has no key and should not need one.
struct Weather: Tool {
    let name = "weather", description = "Weather for a city", access = ToolAccess.readOnly
    let parameters = #"{"type":"object","properties":{"city":{"type":"string"}}}"#
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: "18C and sunny"))
    }
}

@main struct Record {
    static func main() async {
        let file = URL.currentDirectory()
            .appending(path: "Tests/SwacoAITests/Fixtures/muse-spark-1.3-weather.jsonl")
        let real = OpenAI.compatible(
            model: "muse-spark-1.3-contributor",
            endpoint: "https://opencode.ai/zen/go/v1/responses",
            authentication: .bearer(environment: "SWACO_MODEL_KEY"),
            headers: ["x-opencode-session": "swaco-recording"]
        )
        let agent = Agent(
            provider: Recording(real, to: file),
            tools: [Weather()],
            // A vendor asking us to wait is ordinary, and not worth losing a
            // recording over.
            extensions: [Retry(limit: 4, first: .seconds(2))]
        )
        for await event in agent.run("Weather in Paris? Use the tool.").events {
            // A tool run by hand says what went wrong. The system log is the
            // one that keeps content out of it.
            if case .failed(let why) = event {
                print("failed: \(why)")
            } else {
                print(event.kind)
            }
        }
        print("kept in \(file.path())")
    }
}
