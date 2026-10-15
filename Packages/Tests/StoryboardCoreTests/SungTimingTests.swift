import Foundation
import Testing

@testable import StoryboardCore

/// Karaoke: a lyric clip that knows when each of its words was sung.
///
/// Two looks share it — words appearing as they are sung (`Stagger Mode: Sung`)
/// and the whole line on screen lighting up word by word (`Sweep Order: Sung`).
/// Measured on the sprites the evaluator writes, never on the formula.
@Suite("Sung timing")
struct SungTimingTests {
    private typealias P = TextEffect.Param

    /// "ab cd": "ab" sung at 500…900, "cd" at 1500…2300, in clip time.
    private static let sung = [
        SungWord(start: 500, end: 900, characters: 2),
        SungWord(start: 1500, end: 2300, characters: 2),
    ]

    private func sprites(
        _ values: [String: EffectValue] = [:],
        text: String = "ab cd",
        sung: [SungWord]? = SungTimingTests.sung,
    ) -> [StoryboardSprite] {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: 4000)
        node.values = TextEffect.descriptor.defaultValues.merging(values) { _, new in new }
        node.values[P.text] = .text(text)
        node.sungWords = sung
        document[node.id] = node
        return EffectEvaluator().evaluate(document)
    }

    /// When each glyph starts existing: its earliest command.
    private func births(_ sprites: [StoryboardSprite]) -> [Double] {
        sprites.map { $0.commands.map(\.startTime).min() ?? .nan }
    }

    /// When each glyph's highlight starts: its first colour command.
    private func highlights(_ sprites: [StoryboardSprite]) -> [Double] {
        sprites.map { sprite in
            sprite.commands.first { if case .color = $0.payload { true } else { false } }?.startTime ?? .nan
        }
    }

    // ─── From a transcription ────────────────────────────────────────────────

    @Test("words become clip-local timings that count their characters")
    func fromWords() {
        let words = [
            LyricTranscription.Word(text: " Time", start: 10_640, end: 11_540),
            LyricTranscription.Word(text: " went,", start: 11_540, end: 11_900),
        ]

        let sung = SungTiming.words(from: words, clipStart: 10_640)

        #expect(sung == [
            SungWord(start: 0, end: 900, characters: 4),
            SungWord(start: 900, end: 1260, characters: 5),
        ])
    }

    @Test("a word that is only spacing carries no characters and is dropped")
    func dropsEmptyWords() {
        let words = [
            LyricTranscription.Word(text: "落", start: 0, end: 100),
            LyricTranscription.Word(text: " ", start: 100, end: 200),
            LyricTranscription.Word(text: "ち", start: 200, end: 300),
        ]
        #expect(SungTiming.words(from: words, clipStart: 0).map(\.characters) == [1, 1])
    }

    @Test("timings fit the text only while the character count agrees")
    func fits() {
        #expect(SungTiming.fits(Self.sung, text: "ab cd"))
        #expect(SungTiming.fits(Self.sung, text: "ab\ncd"))
        // A typo fixed in place keeps the count, and the timing with it.
        #expect(SungTiming.fits(Self.sung, text: "xy zw"))
        #expect(!SungTiming.fits(Self.sung, text: "ab cde"))
        #expect(!SungTiming.fits([], text: "ab"))
    }

    // ─── Appearing as sung ───────────────────────────────────────────────────

    @Test("each word appears when it was sung")
    func revealsByWord() {
        let born = births(sprites([P.staggerMode: .choice("Sung"), P.unit: .choice("Word")]))
        #expect(born == [500, 500, 1500, 1500])
    }

    @Test("by character, a word's letters spread across its own duration")
    func revealsByCharacter() {
        let born = births(sprites([P.staggerMode: .choice("Sung"), P.unit: .choice("Character")]))
        #expect(born == [500, 700, 1500, 1900])
    }

    @Test("by line, the whole line appears with its first sung word")
    func revealsByLine() {
        let born = births(sprites([P.staggerMode: .choice("Sung"), P.unit: .choice("Line")], text: "ab\ncd"))
        #expect(born == [500, 500, 1500, 1500])
    }

    @Test("Japanese sung glyph by glyph maps one timing per glyph")
    func japaneseGlyphs() {
        let sung = [
            SungWord(start: 100, end: 200, characters: 1),
            SungWord(start: 300, end: 400, characters: 1),
            SungWord(start: 600, end: 700, characters: 1),
        ]
        // One word to the layout — no spaces — but three sung words.
        let born = births(sprites([P.staggerMode: .choice("Sung"), P.unit: .choice("Word")], text: "落ちて", sung: sung))
        #expect(born == [100, 300, 600])
    }

    // ─── Lighting up as sung ─────────────────────────────────────────────────

    @Test("the line is there from the start and each word lights when sung")
    func highlightsByWord() {
        let values: [String: EffectValue] = [
            P.colourMode: .choice("Highlight"), P.sweepOrder: .choice("Sung"), P.unit: .choice("Word"),
        ]
        let drawn = sprites(values)

        #expect(births(drawn) == [0, 0, 0, 0])
        #expect(highlights(drawn) == [500, 500, 1500, 1500])
    }

    @Test("by character the highlight fills each word letter by letter")
    func highlightsByCharacter() {
        let values: [String: EffectValue] = [
            P.colourMode: .choice("Highlight"), P.sweepOrder: .choice("Sung"), P.unit: .choice("Character"),
        ]
        #expect(highlights(sprites(values)) == [500, 700, 1500, 1900])
    }

    // ─── When it cannot apply ────────────────────────────────────────────────

    @Test("text that no longer matches falls back to the ordinary stagger")
    func fallsBackWhenEdited() {
        let sung = sprites([P.staggerMode: .choice("Sung"), P.stagger: .number(100)], text: "ab cde")
        let plain = sprites([P.staggerMode: .choice("Per Unit"), P.stagger: .number(100)], text: "ab cde", sung: nil)
        #expect(births(sung) == births(plain))
    }

    @Test("a clip with no timings falls back to the ordinary sweep")
    func sweepFallsBack() {
        let base: [String: EffectValue] = [P.colourMode: .choice("Highlight")]
        let sung = sprites(base.merging([P.sweepOrder: .choice("Sung")]) { _, new in new }, sung: nil)
        let start = sprites(base.merging([P.sweepOrder: .choice("Start")]) { _, new in new }, sung: nil)
        #expect(highlights(sung) == highlights(start))
    }

    @Test("Sung is offered only where it would do something")
    func offeredOnlyWhenItFits() throws {
        var node = EffectNode(id: "n", type: TextEffect.descriptor.type, name: "t", startTime: 0, duration: 4000)
        node.values[P.text] = .text("ab cd")

        func options(_ id: String) -> [String] {
            TextEffect().descriptor(for: node).parameters.first { $0.id == id }?.options ?? []
        }

        #expect(!options(P.staggerMode).contains("Sung"))
        #expect(!options(P.sweepOrder).contains("Sung"))

        node.sungWords = Self.sung
        #expect(options(P.staggerMode).contains("Sung"))
        #expect(options(P.sweepOrder).contains("Sung"))

        node.values[P.text] = .text("ab cde")
        #expect(!options(P.staggerMode).contains("Sung"))
    }

    // ─── Saving and editing ──────────────────────────────────────────────────

    @Test("timings survive a save, and a node without them writes nothing new")
    func codable() throws {
        var node = EffectNode(id: "n", type: TextEffect.descriptor.type, name: "t", startTime: 0, duration: 4000)
        let plain = try JSONEncoder().encode(node)
        #expect(!String(decoding: plain, as: UTF8.self).contains("sungWords"))

        node.sungWords = Self.sung
        let decoded = try JSONDecoder().decode(EffectNode.self, from: JSONEncoder().encode(node))
        #expect(decoded.sungWords == Self.sung)
        #expect(try JSONDecoder().decode(EffectNode.self, from: plain).sungWords == nil)
    }

    @Test("trimming the start keeps each word on the song, not on the clip")
    func trimKeepsSongTime() throws {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 10_000, duration: 4000)
        node.sungWords = Self.sung
        document[node.id] = node

        document.resize(node.id, startTime: 10_200, duration: 3800)

        let trimmed = try #require(document[node.id]?.sungWords)
        #expect(trimmed.map(\.start) == [300, 1300])
        #expect(trimmed.map(\.end) == [700, 2100])
    }

    @Test("moving the clip carries its words along")
    func moveCarriesWords() {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 10_000, duration: 4000)
        node.sungWords = Self.sung
        document[node.id] = node

        document.move(node.id, to: 12_000)

        #expect(document[node.id]?.sungWords == Self.sung)
    }
}
