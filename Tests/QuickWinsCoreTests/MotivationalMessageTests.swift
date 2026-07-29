import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Motivational messages")
struct MotivationalMessageTests {

    @Test("Every message is at most ten words")
    func messagesRespectTheWordLimit() {
        for message in MotivationalMessage.all {
            let count = MotivationalMessage.wordCount(message)
            #expect(count <= MotivationalMessage.maximumWords, "\"\(message)\" has \(count) words")
            #expect(count > 0)
        }
    }

    @Test("There are enough messages that repeats are not obvious")
    func thereAreEnoughMessages() {
        #expect(MotivationalMessage.all.count >= 10)
        #expect(Set(MotivationalMessage.all).count == MotivationalMessage.all.count)
    }

    @Test("No message claims to know how the work is going")
    func messagesDoNotAssertOutcomes() {
        // The app cannot see the work, so it must not congratulate or evaluate it. Anything that
        // did would sit badly beside an accountability prompt.
        let forbidden = ["great job", "well done", "crushing", "amazing", "you're winning", "success"]
        for message in MotivationalMessage.all {
            let lowered = message.lowercased()
            for phrase in forbidden {
                #expect(!lowered.contains(phrase), "\"\(message)\" evaluates the work")
            }
        }
    }

    @Test("The next message is never the one already on screen")
    func neverRepeatsTheCurrentMessage() {
        var generator = SystemRandomNumberGenerator()
        for current in MotivationalMessage.all {
            for _ in 0..<20 {
                let next = MotivationalMessage.next(after: current, using: &generator)
                #expect(next != current)
            }
        }
    }

    @Test("A message is still produced when the previous one is unknown")
    func handlesNoPreviousMessage() {
        #expect(!MotivationalMessage.next(after: nil).isEmpty)
        #expect(!MotivationalMessage.next(after: "not one of ours").isEmpty)
    }

    @Test("Message settings default to on at fifteen seconds")
    func settingsDefaults() {
        #expect(AppSettings.default.miniHUDMessagesEnabled)
        #expect(AppSettings.default.miniHUDMessageDelay == 15)
    }

    @Test("An out-of-range delay is clamped rather than stored")
    func delayIsClamped() {
        var settings = AppSettings.default
        settings.miniHUDMessageDelay = 0
        #expect(settings.sanitized().miniHUDMessageDelay == 5)
        settings.miniHUDMessageDelay = 99_999
        #expect(settings.sanitized().miniHUDMessageDelay == 300)
    }

    @Test("A settings blob from before messages existed turns them on")
    func olderBlobGetsMessages() throws {
        let older = #"{"menuBarDisplay":"iconOnly"}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(older.utf8))
        #expect(decoded.miniHUDMessagesEnabled)
        #expect(decoded.miniHUDMessageDelay == 15)
    }
}
