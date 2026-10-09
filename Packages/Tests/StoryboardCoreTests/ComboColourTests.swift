import Foundation
import Testing

@testable import StoryboardCore

@Suite("Combo colours")
struct ComboColourTests {
    private let yellow = ComboColour(r: 246, g: 214, b: 122)
    private let blue = ComboColour(r: 52, g: 87, b: 194)
    private let lightBlue = ComboColour(r: 120, g: 193, b: 232)
    private let purple = ComboColour(r: 150, g: 121, b: 192)

    private func parse(_ body: String) -> BeatmapGameplay { OsuGameplayParser.parse(body) }

    private func indices(_ objects: String) -> [Int] {
        parse("[HitObjects]\n\(objects)").hitObjects.map(\.comboIndexWithOffsets)
    }

    // ─── [Colours] ───────────────────────────────────────────────────────────

    @Test("Combo1...N are read in order, tolerating spaces and other keys")
    func palette() {
        let gameplay = parse("""
        [Colours]
        SliderBorder : 1,2,3
        Combo2 : 52,87,194
        Combo1:246, 214 ,122
        """)

        #expect(gameplay.comboColours == [yellow, blue])
    }

    @Test("a map without combo colours gets osu!'s defaults")
    func defaults() {
        #expect(parse("[HitObjects]\n256,192,1,1,0").comboColours == ComboColour.defaults)
        #expect(parse("[Colours]\nSliderBorder : 1,2,3").comboColours == ComboColour.defaults)
        #expect(ComboColour.defaults.first == ComboColour(r: 255, g: 192, b: 0))
        #expect(ComboColour.defaults.count == 4)
    }

    @Test("hostile colour lines are clamped or skipped, never trapping")
    func hostile() {
        let gameplay = parse("""
        [Colours]
        Combo1 : 300,-5,12.6
        Combo2 : nan,1,1
        Combo3 : 1,2
        Combo4 : 1e999,1,1
        Combo9 : 1,2,3
        Combo0 : 1,2,3
        ComboX : 1,2,3
        Combo5 : 9,8,7,255
        """)

        #expect(gameplay.comboColours == [ComboColour(r: 255, g: 0, b: 13), ComboColour(r: 9, g: 8, b: 7)])
    }

    @Test("at most eight combo colours")
    func capped() {
        let lines = (1...20).map { "Combo\($0) : \($0),0,0" }.joined(separator: "\n")

        let colours = parse("[Colours]\n\(lines)").comboColours

        #expect(colours.count == ComboColour.maxCombos)
        #expect(colours.last == ComboColour(r: 8, g: 0, b: 0))
    }

    // ─── Index (ComboIndexWithOffsets) ───────────────────────────────────────

    @Test("the first object is index 1, a new combo adds one, others keep it")
    func indexWalk() {
        // type 1 plain, 5 new combo, 1 plain, 5 new combo
        #expect(indices("0,0,100,1,0\n0,0,200,1,0\n0,0,300,5,0\n0,0,400,1,0\n0,0,500,5,0") == [1, 1, 2, 2, 3])
    }

    @Test("combo skip bits advance the colour on a new combo")
    func skip() {
        // 5 | (2 << 4) = 37: new combo skipping two colours.
        #expect(indices("0,0,100,1,0\n0,0,200,37,0\n0,0,300,1,0\n0,0,400,5,0") == [1, 4, 4, 5])
    }

    @Test("a skip without a new combo does nothing")
    func skipWithoutNewCombo() {
        // 1 | (3 << 4) = 49, not a new combo.
        #expect(indices("0,0,100,1,0\n0,0,200,49,0") == [1, 1])
    }

    @Test("the object after a spinner starts a new combo (a plain spinner keeps the index)")
    func spinner() {
        // A spinner (type 8) forces a new combo on the next plain object.
        #expect(indices("0,0,100,1,0\n0,0,200,8,0,900\n0,0,1000,1,0\n0,0,1100,1,0") == [1, 1, 2, 2])
    }

    // osu!lazer `OsuHitObject.UpdateComboInformation`: "spinners never start a
    // new combo even if they are flagged as doing so". A map that opens on a
    // flagged spinner (Constellations does) starts its colours one later than
    // a walk that counts it.
    @Test("a spinner flagged as a new combo does not advance the colour")
    func flaggedSpinner() {
        // 12 = spinner + new combo; 5 = circle + new combo.
        #expect(indices("256,192,100,12,0,900\n0,0,1000,1,0\n0,0,1100,5,0\n256,192,1200,12,0,1500\n0,0,1600,1,0")
            == [0, 1, 2, 2, 3])
    }

    // `ConvertHitObjectParser`: `ComboOffset = newCombo ? comboOffset : 0`, the
    // flag as written. A combo forced by a spinner does not read skip bits.
    @Test("a combo forced by a spinner ignores skip bits it was not flagged with")
    func forcedComboIgnoresSkip() {
        // 1 | (3 << 4) = 49: skip bits without the new-combo flag.
        #expect(indices("256,192,100,8,0,900\n0,0,1000,49,0") == [0, 1])
    }

    // ─── Picking ─────────────────────────────────────────────────────────────

    // `LegacySkin.GetComboColour`: `ComboColours[colourIndex % count]`, with
    // `LegacyBeatmapSkin` passing `ComboIndexWithOffsets`. No -1: that one is the
    // editor's new-combo button, not what gameplay draws.
    @Test("the colour is the palette at index modulo its size")
    func pick() {
        let palette = [yellow, blue, lightBlue, purple]

        #expect(ComboColour.pick(from: palette, indexWithOffsets: 0) == yellow)
        #expect(ComboColour.pick(from: palette, indexWithOffsets: 1) == blue)
        #expect(ComboColour.pick(from: palette, indexWithOffsets: 3) == purple)
        #expect(ComboColour.pick(from: palette, indexWithOffsets: 4) == yellow)
    }

    @Test("a short palette wraps by its own size and an empty one uses the defaults")
    func pickSmall() {
        #expect(ComboColour.pick(from: [yellow, blue], indexWithOffsets: 3) == blue)
        #expect(ComboColour.pick(from: [], indexWithOffsets: 1) == ComboColour.defaults[1])
        #expect(ComboColour.pick(from: [yellow], indexWithOffsets: Int.min) == yellow)
        #expect(ComboColour.pick(from: [yellow, blue], indexWithOffsets: -1) == blue)
    }

    // ─── Real map ────────────────────────────────────────────────────────────

    /// The objects in the user's osu!lazer capture at ~163.9 s of
    /// "Constellations (The Cube) [8]" (third-party map; only these lines are
    /// kept). The real file opens on a flagged spinner, and the walk reaches
    /// index 222 at (393,134); the spinner plus 221 new combos reproduce it. The
    /// capture shows them light blue, purple and yellow: Combo3, Combo4, Combo1.
    @Test("objects of the real map land on the colours the capture shows")
    func realMap() throws {
        let opening = "256,192,156,12,0,2556"
        let prefix = opening + "\n" + (0..<221).map { "0,0,\(3000 + $0 * 5),5,0" }.joined(separator: "\n")
        let real = """
        549,100,5000,5,2
        437,141,5100,1,2
        393,134,5200,1,2,1:3:0:0:
        355,160,5300,1,2,0:3:0:0:
        308,228,5400,5,8,1:2:0:0:
        260,225,5500,1,8,1:2:0:0:
        191,240,5600,5,8,1:0:0:0:
        142,236,5700,1,8,1:0:0:0:
        """
        let gameplay = parse("""
        [Colours]
        Combo1 : 246,214,122
        Combo2 : 52,87,194
        Combo3 : 120,193,232
        Combo4 : 150,121,192

        [HitObjects]
        \(prefix)
        \(real)
        """)

        func colour(atX x: Double) throws -> ComboColour {
            gameplay.comboColour(for: try #require(gameplay.hitObjects.first { $0.position.x == x }))
        }

        #expect(try colour(atX: 393) == lightBlue)
        #expect(try colour(atX: 355) == lightBlue)
        #expect(try colour(atX: 308) == purple)
        #expect(try colour(atX: 260) == purple)
        #expect(try colour(atX: 191) == yellow)
        #expect(try colour(atX: 142) == yellow)
    }

    @Test("the extracted fixture reads the map's palette and walks its first objects")
    func fixture() throws {
        let url = try #require(
            Bundle.module.url(forResource: "constellations-sliders", withExtension: "osu", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "constellations-sliders", withExtension: "osu"),
        )
        let gameplay = parse(try String(contentsOf: url, encoding: .utf8))

        #expect(gameplay.comboColours == [yellow, blue, lightBlue, purple])
        // 2728 new combo, 4099 new combo, 5128 plain, 8728 plain, 9242 plain, 10956 new combo.
        let walked = gameplay.hitObjects.prefix(6).map(\.comboIndexWithOffsets)
        #expect(walked == [1, 2, 2, 2, 2, 3])
        #expect(gameplay.comboColour(for: gameplay.hitObjects[0]) == blue)
        #expect(gameplay.comboColour(for: gameplay.hitObjects[5]) == purple)
    }
}
