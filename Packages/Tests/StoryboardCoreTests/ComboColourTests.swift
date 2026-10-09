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

    // ─── Picking ─────────────────────────────────────────────────────────────

    @Test("index 1 is Combo1 and the palette wraps")
    func pick() {
        let palette = [yellow, blue, lightBlue, purple]

        #expect(ComboColour.pick(from: palette, indexWithOffsets: 1) == yellow)
        #expect(ComboColour.pick(from: palette, indexWithOffsets: 4) == purple)
        #expect(ComboColour.pick(from: palette, indexWithOffsets: 5) == yellow)
        #expect(ComboColour.pick(from: palette, indexWithOffsets: 6) == blue)
    }

    @Test("a short palette wraps by its own size and an empty one uses the defaults")
    func pickSmall() {
        #expect(ComboColour.pick(from: [yellow, blue], indexWithOffsets: 3) == yellow)
        #expect(ComboColour.pick(from: [], indexWithOffsets: 1) == ComboColour.defaults[0])
        #expect(ComboColour.pick(from: [yellow], indexWithOffsets: Int.min) == yellow)
    }

    // ─── Real map ────────────────────────────────────────────────────────────

    /// Objects 3-4 of combo 224, and the two pairs after it, from
    /// "Constellations (The Cube) [8]" (third-party map; only these lines are
    /// kept). In the real file the walk from the first object reaches index 224
    /// at (393,134); 223 plain new combos in front reproduce it, so the colour
    /// is the one osu! picks there: Combo4, then Combo1, then Combo2.
    @Test("objects of the real map land on the colours the rule gives")
    func realMap() throws {
        let prefix = (0..<223).map { "0,0,\($0 * 5),5,0" }.joined(separator: "\n")
        let real = """
        549,100,2000,5,2
        437,141,2100,1,2
        393,134,2200,1,2,1:3:0:0:
        355,160,2300,1,2,0:3:0:0:
        308,228,2400,5,8,1:2:0:0:
        260,225,2500,1,8,1:2:0:0:
        191,240,2600,5,8,1:0:0:0:
        142,236,2700,1,8,1:0:0:0:
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

        #expect(try colour(atX: 393) == purple)
        #expect(try colour(atX: 355) == purple)
        #expect(try colour(atX: 308) == yellow)
        #expect(try colour(atX: 260) == yellow)
        #expect(try colour(atX: 191) == blue)
        #expect(try colour(atX: 142) == blue)
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
        #expect(gameplay.comboColour(for: gameplay.hitObjects[0]) == yellow)
        #expect(gameplay.comboColour(for: gameplay.hitObjects[5]) == lightBlue)
    }
}
