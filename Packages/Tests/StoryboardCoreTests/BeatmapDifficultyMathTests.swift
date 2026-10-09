import Testing

@testable import StoryboardCore

@Suite("Difficulty math")
struct BeatmapDifficultyMathTests {
    @Test("radius = 54.4 - 4.48 * CS, pinned at CS 0, 4 and 10")
    func radius() {
        #expect(abs(BeatmapDifficultyMath.radius(cs: 0) - 54.4) < 1e-9)
        #expect(abs(BeatmapDifficultyMath.radius(cs: 4) - 36.48) < 1e-9)
        #expect(abs(BeatmapDifficultyMath.radius(cs: 10) - 9.6) < 1e-9)
    }

    @Test("a non-finite or out-of-range CS is clamped, never NaN")
    func radiusClamped() {
        #expect(BeatmapDifficultyMath.radius(cs: .nan).isFinite)
        #expect(BeatmapDifficultyMath.radius(cs: -50) == BeatmapDifficultyMath.radius(cs: 0))
        #expect(BeatmapDifficultyMath.radius(cs: 50) == BeatmapDifficultyMath.radius(cs: 10))
    }

    @Test("preempt covers both sides of AR 5")
    func preempt() {
        #expect(BeatmapDifficultyMath.preempt(ar: 0) == 1800)
        #expect(BeatmapDifficultyMath.preempt(ar: 5) == 1200)
        #expect(BeatmapDifficultyMath.preempt(ar: 9) == 600)
        #expect(BeatmapDifficultyMath.preempt(ar: 10) == 450)
        // Between: AR 2.5 -> halfway to 1800.
        #expect(BeatmapDifficultyMath.preempt(ar: 2.5) == 1500)
        #expect(BeatmapDifficultyMath.preempt(ar: 7.5) == 825)
    }

    @Test("fade-in is 400ms, shorter when the preempt is under 450")
    func fadeIn() {
        #expect(BeatmapDifficultyMath.fadeIn(preempt: 1200) == 400)
        #expect(BeatmapDifficultyMath.fadeIn(preempt: 450) == 400)
        #expect(BeatmapDifficultyMath.fadeIn(preempt: 225) == 200)
    }

    @Test("the approach circle goes from 4x to 1x over the preempt (S1.8b)")
    func approachScale() {
        #expect(BeatmapDifficultyMath.approachScale(timeBeforeHit: 600, preempt: 600) == 4)
        #expect(BeatmapDifficultyMath.approachScale(timeBeforeHit: 300, preempt: 600) == 2.5)
        #expect(BeatmapDifficultyMath.approachScale(timeBeforeHit: 0, preempt: 600) == 1)
        // Outside the window it clamps instead of growing or shrinking.
        #expect(BeatmapDifficultyMath.approachScale(timeBeforeHit: 5000, preempt: 600) == 4)
        #expect(BeatmapDifficultyMath.approachScale(timeBeforeHit: -100, preempt: 600) == 1)
        #expect(BeatmapDifficultyMath.approachScale(timeBeforeHit: .nan, preempt: 600).isFinite)
    }
}
