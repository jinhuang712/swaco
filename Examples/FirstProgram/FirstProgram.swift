import Swaco
import SwacoOpenAI

struct Weather: Tool {
    let name = "weather", description = "Weather for a city", access = ToolAccess.readOnly
    let parameters = #"{"type":"object","properties":{"city":{"type":"string"}}}"#
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: "18C and sunny"))
    }
}

@main struct FirstProgram {
    static func main() async {
        let model = OpenAI.compatible(model: "muse-spark-1.3-contributor",
            endpoint: "https://opencode.ai/zen/go/v1/responses",
            authentication: .bearer(environment: "SWACO_MODEL_KEY"),
            headers: ["x-opencode-session": "swaco-first-program"])
        for await event in Agent(provider: model, tools: [Weather()]).run("Weather in Paris?").events { print(event) }
    }
}
