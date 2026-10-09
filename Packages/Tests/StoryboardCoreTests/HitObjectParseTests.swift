import Testing

@testable import StoryboardCore

@Suite("Hit object parsing")
struct HitObjectParseTests {
    private func objects(_ body: String) -> [HitObject] {
        OsuGameplayParser.parse("[HitObjects]\n\(body)").hitObjects
    }

    @Test("a circle (S1.3a)")
    func circle() throws {
        let object = try #require(objects("256,192,1000,1,0").first)

        #expect(object.position == PlayfieldPoint(x: 256, y: 192))
        #expect(object.time == 1000)
        #expect(object.kind == .circle)
        #expect(!object.newCombo)
    }

    @Test("a bezier slider (S1.3b)")
    func slider() throws {
        let object = try #require(objects("100,100,2000,2,0,B|200:100|200:200,1,150").first)

        guard case let .slider(slider) = object.kind else {
            Issue.record("expected a slider")
            return
        }
        #expect(slider.curve == .bezier)
        #expect(slider.points == [PlayfieldPoint(x: 200, y: 100), PlayfieldPoint(x: 200, y: 200)])
        #expect(slider.slides == 1)
        #expect(slider.pixelLength == 150)
    }

    @Test("every curve letter, and an unknown one skips the line")
    func curveTypes() {
        let kinds = ["L": CurveType.linear, "P": .perfect, "B": .bezier, "C": .catmull]
        for (letter, expected) in kinds {
            let object = objects("0,0,0,2,0,\(letter)|10:10,1,10").first
            guard case let .slider(slider)? = object?.kind else {
                Issue.record("\(letter) did not parse")
                continue
            }
            #expect(slider.curve == expected)
        }
        #expect(objects("0,0,0,2,0,X|10:10,1,10").isEmpty)
    }

    @Test("a spinner (S1.3c)")
    func spinner() throws {
        let object = try #require(objects("256,192,3000,12,0,5000").first)

        #expect(object.kind == .spinner(endTime: 5000))
        #expect(object.time == 3000)
    }

    @Test("hold notes are ignored")
    func holdNotes() {
        #expect(objects("64,192,1000,128,0,2000:0:0:0:0:").isEmpty)
    }

    @Test("extras and hitsound fields do not matter")
    func extras() {
        #expect(objects("256,192,1000,1,2,3:0:0:0:").count == 1)
        #expect(objects("256,192,1000,1,2,0:0:0:0:extra,junk").count == 1)
    }

    @Test("sorted by time, equal times keep file order (S1.3d)")
    func stableSort() {
        let parsed = objects("""
        10,10,2000,1,0
        20,20,1000,1,0
        30,30,2000,1,0
        40,40,2000,1,0
        50,50,1000,1,0
        """)

        #expect(parsed.map(\.position.x) == [20, 50, 10, 30, 40])
    }

    @Test("stable sort holds on a big run of equal times")
    func stableSortBig() {
        let lines = (0..<500).map { "\($0),0,1000,1,0" }.joined(separator: "\n")

        #expect(objects(lines).map(\.position.x) == (0..<500).map(Double.init))
    }

    @Test("combo numbers reset on new combo, skip bits are exposed (S1.3e)")
    func combo() {
        let parsed = objects("""
        0,0,100,5,0
        0,0,200,1,0
        0,0,300,1,0
        0,0,400,37,0
        0,0,500,1,0
        """)

        #expect(parsed.map(\.comboNumber) == [1, 2, 3, 1, 2])
        #expect(parsed.map(\.newCombo) == [true, false, false, true, false])
        #expect(parsed.map(\.comboSkip) == [0, 0, 0, 2, 0])
    }

    @Test("the object after a spinner starts a new combo, as in osu!")
    func spinnerForcesCombo() {
        let parsed = objects("""
        0,0,100,5,0
        0,0,200,8,0,900
        0,0,1000,1,0
        """)

        #expect(parsed.map(\.comboNumber) == [1, 2, 1])
    }
}
