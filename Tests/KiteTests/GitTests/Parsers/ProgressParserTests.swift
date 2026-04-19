import Foundation
import Testing
@testable import Kite

@Suite("ProgressParser")
struct ProgressParserTests {
    @Test("two distinct \\r-delimited lines produce two events (VAL-PARSE-006)")
    func rDedupYieldsDistinctEvents() throws {
        let parser = ProgressParser()
        let chunk = "Receiving objects:  1% (10/1000)\rReceiving objects:  2% (20/1000)\r"
        let latest = parser.consume(chunk)
        let event = try #require(latest)
        #expect(event.phase == "Receiving objects")
        #expect(event.percent == 2)
    }

    @Test("two consumes at the same percent emit only once (dedup)")
    func dedupSamePercent() {
        let parser = ProgressParser()
        let first = parser.consume("Receiving objects:  42% (420/1000)\r")
        #expect(first?.percent == 42)
        let second = parser.consume("Receiving objects:  42% (420/1000)\r")
        #expect(second == nil, "same (phase, percent) should dedup to nil")
    }

    @Test("phase transition emits a new event even at same percent")
    func phaseTransitionResetsDedup() throws {
        let parser = ProgressParser()
        _ = parser.consume("Counting objects: 100% (50/50), done.\r")
        let next = parser.consume("Compressing objects: 100% (40/40), done.\r")
        let event = try #require(next)
        #expect(event.phase == "Compressing objects")
        #expect(event.percent == 100)
    }

    @Test("unparseable line returns nil")
    func unparseableReturnsNil() {
        let parser = ProgressParser()
        let event = parser.consume("some random gibberish with no colon\n")
        #expect(event == nil)
    }

    @Test("remote: prefix is stripped from phase but retained in raw")
    func remotePrefixStripped() throws {
        let parser = ProgressParser()
        let raw = parser.consume("remote: Counting objects:  25% (10/40)\r")
        let event = try #require(raw)
        #expect(event.phase == "Counting objects")
        #expect(event.percent == 25)
        #expect(event.raw.contains("remote: Counting objects"))
    }

    @Test("status line without percentage yields phase event with nil percent")
    func noPercentageYieldsNilPercent() throws {
        let parser = ProgressParser()
        let raw = parser.consume("remote: Enumerating objects: 42, done.\n")
        let event = try #require(raw)
        #expect(event.phase == "Enumerating objects")
        #expect(event.percent == nil)
    }

    @Test("partial chunk without terminator is buffered until a separator arrives")
    func partialChunkBuffered() throws {
        let parser = ProgressParser()
        let noEvent = parser.consume("Receiving objects:  1% ")
        #expect(noEvent == nil, "no separator yet — should buffer")
        let raw = parser.consume("(10/1000)\r")
        let event = try #require(raw)
        #expect(event.phase == "Receiving objects")
        #expect(event.percent == 1)
    }

    @Test("empty input returns nil")
    func emptyReturnsNil() {
        let parser = ProgressParser()
        #expect(parser.consume("") == nil)
    }
}
