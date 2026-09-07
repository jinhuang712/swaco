import Foundation
import Swaco
import SwacoExtensions
import SwacoAnthropic
import SwacoOpenAI

/// Points the first program's shape at whichever model is named on the command
/// line, so a new model is one argument rather than one branch.
struct Weather: Tool {
    let name = "weather", description = "Weather for a city", access = ToolAccess.readOnly
    let parameters = #"{"type":"object","properties":{"city":{"type":"string"}}}"#
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: "18C and sunny"))
    }
}

@main struct Try {
    static func main() async {
        let model = CommandLine.arguments.dropFirst().first ?? "deepseek-v4-flash"
        // One vocabulary, three protocols, and the app names which. Nothing
        // above this line changes when the model does.
        let provider: any Provider = switch CommandLine.arguments.dropFirst().dropFirst().first ?? "chat" {
        case "messages":
            Anthropic.compatible(
                model: model,
                endpoint: "https://opencode.ai/zen/go/v1/messages",
                authentication: .apiKey(
                    ProcessInfo.processInfo.environment["SWACO_MODEL_KEY"] ?? "",
                    header: Anthropic.keyHeader
                ),
                headers: ["x-opencode-session": "swaco-try"],
                maxTokens: 1024
            )
        case "responses":
            OpenAI.compatible(
                model: model,
                endpoint: "https://opencode.ai/zen/go/v1/responses",
                authentication: .bearer(environment: "SWACO_MODEL_KEY"),
                headers: ["x-opencode-session": "swaco-try"],
                maxOutputTokens: 1024
            )
        default:
            OpenAI.chatCompletions(
                model: model,
                endpoint: "https://opencode.ai/zen/go/v1/chat/completions",
                authentication: .bearer(environment: "SWACO_MODEL_KEY"),
                headers: ["x-opencode-session": "swaco-try"],
                maxTokens: 1024
            )
        }
        let agent = Agent(provider: provider, tools: [Weather()],
                          extensions: [Retry(limit: 4, first: .seconds(2))])
        for await event in agent.run("Weather in Paris? Use the tool, then answer in one line.").events {
            switch event {
            case .text(let piece): print(piece, terminator: "")
            case .toolCallIssued(let call): print("\n[calls \(call.name) with \(call.arguments)]")
            case .toolResultArrived(let result): print("[tool said \(result.content)]")
            case .usage(let usage): print("\n[\(usage.totalTokens) tokens, \(usage.reasoningTokens) thinking]")
            case .failed(let why): print("\n[failed: \(why)]")
            case .finished: print("\n[done]")
            default: break
            }
        }
    }
}
