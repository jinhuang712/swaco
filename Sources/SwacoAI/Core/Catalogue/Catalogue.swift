import Foundation
import Swaco

/// The models we happen to know about, as data.
///
/// A convenience and never an authority. Vendors add models weekly and change
/// what they can do; an app that wants a model this list has never heard of
/// writes one down itself and loses nothing. Swaco favours no provider, so
/// nothing here is a default and the order means nothing.
public enum Catalogue {
    /// Every model this version was told about.
    public static let all: [Model] = openAI + anthropic + apple

    /// A model by identifier, whoever serves it.
    public static func model(_ identifier: String) -> Model? {
        all.first { $0.identifier == identifier }
    }

    /// Every model one provider serves.
    public static func models(from provider: String) -> [Model] {
        all.filter { $0.provider == provider }
    }

    public static let openAI: [Model] = [
        Model(provider: "openai", identifier: "gpt-5.2",
              capabilities: ModelCapabilities(tools: true, vision: true, reasoning: true,
                                              providerExecutedTools: true, contextSize: 400_000)),
        Model(provider: "openai", identifier: "gpt-5.2-mini",
              capabilities: ModelCapabilities(tools: true, vision: true, reasoning: true,
                                              providerExecutedTools: false, contextSize: 400_000)),
    ]

    public static let anthropic: [Model] = [
        Model(provider: "anthropic", identifier: "claude-fable-5-1",
              capabilities: ModelCapabilities(tools: true, vision: true, reasoning: true,
                                              providerExecutedTools: true, contextSize: 200_000)),
        Model(provider: "anthropic", identifier: "claude-opus-5",
              capabilities: ModelCapabilities(tools: true, vision: true, reasoning: true,
                                              providerExecutedTools: true, contextSize: 200_000)),
        Model(provider: "anthropic", identifier: "claude-sonnet-5",
              capabilities: ModelCapabilities(tools: true, vision: true, reasoning: true,
                                              providerExecutedTools: true, contextSize: 200_000)),
    ]

    /// On-device, and one provider among others. It runs tools itself rather
    /// than handing calls back, which is why it declares none.
    public static let apple: [Model] = [
        Model(provider: "apple", identifier: "system-language-model",
              capabilities: ModelCapabilities(tools: false, vision: false, reasoning: false,
                                              providerExecutedTools: false, contextSize: 4_096)),
    ]
}
