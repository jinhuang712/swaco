import Foundation
import Testing
import Swaco

/// A tool's answer has two readers who want different things, and swaco
/// carries both rather than choosing.
@Suite struct WhatAToolProduced {
    private struct Day: Codable, Sendable, Hashable {
        let title: String
        let hour: Int
    }

    @Test func atoolMayAnswerWithAShapeAndWordsAtOnce() throws {
        let day = [Day(title: "lunch", hour: 13), Day(title: "dentist", hour: 15)]
        let result = try ToolResult(callID: "c", day, saying: "two things on")

        // The model is told what a model reads best.
        #expect(result.content == "two things on")
        // The app gets what a screen reads best.
        #expect(try result.data(as: [Day].self) == day)
    }

    /// With nothing better to say, the structure is what the model is told.
    @Test func theWordsDefaultToTheStructure() throws {
        let result = try ToolResult(callID: "c", ["a": 1])
        #expect(result.content.contains("\"a\""))
        #expect(result.data != nil)
    }

    /// A tool that only has words is unchanged, and has no structure to read.
    @Test func atoolWithOnlyWordsIsUnchanged() throws {
        let result = ToolResult(callID: "c", content: "18C and sunny")
        #expect(result.content == "18C and sunny")
        #expect(result.data == nil)
        #expect(try result.data(as: [Day].self) == nil)
    }

    /// The structure travels in the log, so an app reading a history later
    /// has it as well as the words.
    @Test func thestructureSurvivesTheLog() throws {
        let result = try ToolResult(callID: "c", Day(title: "lunch", hour: 13), saying: "lunch at one")
        let event = Event.toolResultArrived(result)
        let written = try JSONEncoder().encode(event)
        let read = try JSONDecoder().decode(Event.self, from: written)
        #expect(read == event)
        guard case .toolResultArrived(let same) = read else {
            Issue.record("a result must come back as a result")
            return
        }
        #expect(try same.data(as: Day.self) == Day(title: "lunch", hour: 13))
    }
}
