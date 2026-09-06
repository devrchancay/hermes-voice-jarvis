//  Unit tests for sentence chunking and spoken-text sanitising. No audio playback.

import XCTest

@testable import HermesVoice

final class SentenceBufferTests: XCTestCase {

    func testEmitsSentenceOnTerminator() {
        var buffer = SentenceBuffer()
        XCTAssertEqual(buffer.append("Hello"), [])
        XCTAssertEqual(buffer.append(" there"), [])
        XCTAssertEqual(buffer.append("."), ["Hello there."])
    }

    func testEmitsMultipleSentencesFromOneToken() {
        var buffer = SentenceBuffer()
        XCTAssertEqual(buffer.append("One. Two. Three."), ["One.", "Two.", "Three."])
    }

    func testKeepsPartialSentenceBuffered() {
        var buffer = SentenceBuffer()
        XCTAssertEqual(buffer.append("Complete. Partial"), ["Complete."])
        XCTAssertEqual(buffer.flush(), "Partial")
    }

    func testFlushReturnsNilWhenEmpty() {
        var buffer = SentenceBuffer()
        XCTAssertNil(buffer.flush())
        _ = buffer.append("x.")
        XCTAssertNil(buffer.flush(), "The terminator already drained the buffer")
    }

    func testHandlesQuestionAndExclamation() {
        var buffer = SentenceBuffer()
        XCTAssertEqual(buffer.append("¿Qué tal?"), ["¿Qué tal?"])
        XCTAssertEqual(buffer.append("¡Genial!"), ["¡Genial!"])
    }

    func testHandlesNewlineAsTerminator() {
        var buffer = SentenceBuffer()
        XCTAssertEqual(buffer.append("Line one\n"), ["Line one"])
    }

    // MARK: Non-Western punctuation

    func testHandlesCJKPunctuation() {
        var buffer = SentenceBuffer()
        XCTAssertEqual(buffer.append("こんにちは。"), ["こんにちは。"])
        XCTAssertEqual(buffer.append("元気ですか？"), ["元気ですか？"])
    }

    func testHandlesDevanagariDanda() {
        var buffer = SentenceBuffer()
        XCTAssertEqual(buffer.append("नमस्ते।"), ["नमस्ते।"])
    }

    func testHandlesArabicFullStop() {
        var buffer = SentenceBuffer()
        XCTAssertEqual(buffer.append("مرحبا۔"), ["مرحبا۔"])
    }

    // MARK: Length cap

    func testFlushesAtWordBoundaryWhenNoTerminatorArrives() throws {
        var buffer = SentenceBuffer()
        buffer.maxLength = 20

        // Text that never terminates must still be spoken, not buffered forever.
        let emitted = buffer.append("one two three four five six seven")
        let chunk = try XCTUnwrap(emitted.first, "The length cap must force a flush")

        XCTAssertFalse(chunk.hasSuffix(" "))
        // The split lands on a space, so the trailing word stays whole in the buffer.
        XCTAssertFalse(chunk.hasSuffix("sev"))
        XCTAssertEqual(try XCTUnwrap(buffer.flush()), "seven")
    }

    func testLengthCapFallsBackToHardSplitWithoutSpaces() {
        var buffer = SentenceBuffer()
        buffer.maxLength = 10
        let emitted = buffer.append(String(repeating: "あ", count: 15))
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted.first?.count, 15)
    }

    func testStreamedTokensReassembleIntoOriginalText() {
        var buffer = SentenceBuffer()
        let source = "Primera oración. Segunda oración! ¿Tercera?"
        var spoken: [String] = []

        // Feed it the way SSE does: a few characters at a time.
        for chunk in source.chunked(into: 3) {
            spoken.append(contentsOf: buffer.append(chunk))
        }
        if let tail = buffer.flush() { spoken.append(tail) }

        XCTAssertEqual(spoken, ["Primera oración.", "Segunda oración!", "¿Tercera?"])
    }
}

final class SpokenTextSanitizerTests: XCTestCase {
    func testStripsMarkdownEmphasis() {
        XCTAssertEqual(SpokenTextSanitizer.sanitize("**bold** and _italic_"), "bold and italic")
    }

    func testStripsCodeAndHeadings() {
        XCTAssertEqual(SpokenTextSanitizer.sanitize("`code`"), "code")
        XCTAssertEqual(SpokenTextSanitizer.sanitize("## Heading"), "Heading")
    }

    func testPreservesRegularPunctuation() {
        let text = "¿Cómo estás? ¡Bien, gracias!"
        XCTAssertEqual(SpokenTextSanitizer.sanitize(text), text)
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(SpokenTextSanitizer.sanitize("  hola  "), "hola")
    }
}

private extension String {
    /// Splits into fixed-size chunks, mimicking token-by-token arrival.
    func chunked(into size: Int) -> [String] {
        var result: [String] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[index..<next]))
            index = next
        }
        return result
    }
}
