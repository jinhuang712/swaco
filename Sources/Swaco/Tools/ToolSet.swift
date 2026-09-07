import Foundation

/// A named group of tools.
///
/// A single tool is a toolset of one, which is why `Tool` is a `ToolSet`: an
/// app hands over whatever it has, one tool or a whole framework's worth, and
/// nothing has to be wrapped to fit.
///
/// A toolset is coarse on purpose. Fewer, broader capabilities beat many
/// narrow ones, and an app that wants only part of one says so at the
/// granularity of a tool rather than being offered forty variants.
public protocol ToolSet: Sendable {
    var name: String { get }
    var description: String { get }
    /// What the model is actually offered.
    var tools: [any Tool] { get }
}

public extension ToolSet {
    /// The same set, cut down to the tools named. What an app uses when it
    /// wants a framework's reading tools and none of its writing ones.
    func only(_ names: Set<String>) -> some ToolSet {
        Chosen(from: self, keeping: { names.contains($0.name) })
    }

    /// The same set, without the tools named.
    func except(_ names: Set<String>) -> some ToolSet {
        Chosen(from: self, keeping: { !names.contains($0.name) })
    }

    /// The same set, cut down to what a rule keeps. The rule reads the facts
    /// a tool declares, its name and its access, and nothing else.
    func keeping(_ rule: @Sendable @escaping (any Tool) -> Bool) -> some ToolSet {
        Chosen(from: self, keeping: rule)
    }
}

/// Part of a toolset, chosen by the app.
struct Chosen<Whole: ToolSet>: ToolSet {
    let whole: Whole
    let rule: @Sendable (any Tool) -> Bool

    init(from whole: Whole, keeping rule: @Sendable @escaping (any Tool) -> Bool) {
        self.whole = whole
        self.rule = rule
    }

    var name: String { whole.name }
    var description: String { whole.description }
    var tools: [any Tool] { whole.tools.filter(rule) }
}

public extension Array where Element == any ToolSet {
    /// Every tool in every set, in the order the app listed them. Two tools
    /// with one name is the app's mistake to see, so the first wins and the
    /// duplicate is dropped rather than shadowing it silently at call time.
    var tools: [any Tool] {
        var seen: Set<String> = []
        return flatMap(\.tools).filter { seen.insert($0.name).inserted }
    }
}
