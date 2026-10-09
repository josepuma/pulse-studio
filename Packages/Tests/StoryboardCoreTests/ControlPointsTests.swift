import Testing

@testable import StoryboardCore

@Suite("Gameplay control points")
struct ControlPointsTests {
    private func points(_ body: String) -> ControlPoints {
        OsuGameplayParser.parse("[TimingPoints]\n\(body)").controlPoints
    }

    @Test("a green point exposes its SV and leaves the red list as the old parser read it (S1.2a)")
    func greenAndRed() {
        let source = "[TimingPoints]\n1000,500,4,1,0,60,1,0\n2000,-50,4,1,0,60,0,0"
        let controlPoints = OsuGameplayParser.parse(source).controlPoints
        let legacy = OsuParser.parse(source).uninheritedPoints

        #expect(controlPoints.sv(at: 2500) == 2.0)
        #expect(controlPoints.sv(at: 1500) == 1.0)
        #expect(controlPoints.red == legacy)
    }

    @Test("unusable green points are skipped (S1.2b)")
    func unusableGreens() {
        let cp = points("""
        0,500,4,1,0,60,1,0
        100,0,4,1,0,60,0,0
        200,nan,4,1,0,60,0,0
        300,250,4,1,0,60,0,0
        400,-inf,4,1,0,60,0,0
        """)

        #expect(cp.green.isEmpty)
        #expect(cp.sv(at: 500) == 1.0)
    }

    @Test("the latest green after the governing red wins, a later red resets (S1.2c)")
    func resolution() {
        let cp = points("""
        1000,500,4,1,0,60,1,0
        1500,-50,4,1,0,60,0,0
        2000,-200,4,1,0,60,0,0
        3000,400,4,1,0,60,1,0
        """)

        #expect(cp.sv(at: 500) == 1.0)
        #expect(cp.sv(at: 1500) == 2.0)
        #expect(cp.sv(at: 2500) == 0.5)
        // The red at 3000 resets the multiplier even though greens came before.
        #expect(cp.sv(at: 3000) == 1.0)
        #expect(cp.sv(at: 9000) == 1.0)
    }

    @Test("a green at the same time as its red applies")
    func sameTime() {
        let cp = points("1000,500,4,1,0,60,1,0\n1000,-50,4,1,0,60,0,0")

        #expect(cp.sv(at: 1000) == 2.0)
    }

    @Test("SV is clamped to 0.1...10")
    func svClamp() {
        let cp = points("0,500,4,1,0,60,1,0\n100,-1,4,1,0,60,0,0\n200,-100000,4,1,0,60,0,0")

        #expect(cp.sv(at: 150) == ControlPoints.svRange.upperBound)
        #expect(cp.sv(at: 250) == ControlPoints.svRange.lowerBound)
    }

    @Test("the beat length falls back to the first red point, then to a default (S1.6c core)")
    func beatLength() {
        let cp = points("1000,400,4,1,0,60,1,0\n3000,600,4,1,0,60,1,0")

        #expect(cp.beatLength(at: 0) == 400)
        #expect(cp.beatLength(at: 2000) == 400)
        #expect(cp.beatLength(at: 3000) == 600)
        #expect(points("").beatLength(at: 1234) == ControlPoints.defaultBeatLength)
        #expect(ControlPoints.defaultBeatLength == 500)
    }
}
