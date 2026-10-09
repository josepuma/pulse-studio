import Testing

@testable import StoryboardCore

@Suite("Slider timing")
struct SliderTimingTests {
    @Test("140px at multiplier 1.4, SV 1, 500ms beats lasts 500ms (S1.6a)")
    func base() {
        let span = SliderTiming.spanDuration(pixelLength: 140, sv: 1, multiplier: 1.4, beatLength: 500)
        #expect(abs(span - 500) < 1e-9)
    }

    @Test("SV 2 halves it and slides multiply it (S1.6b)")
    func svAndSlides() {
        let span = SliderTiming.spanDuration(pixelLength: 140, sv: 2, multiplier: 1.4, beatLength: 500)
        #expect(abs(span - 250) < 1e-9)
        let total = SliderTiming.totalDuration(
            pixelLength: 140, slides: 3, sv: 2, multiplier: 1.4, beatLength: 500,
        )
        #expect(abs(total - 750) < 1e-9)
    }

    @Test("non-finite or zero inputs give the minimum positive duration")
    func degenerate() {
        let minimum = SliderTiming.minimumSpanDuration
        #expect(minimum > 0)
        #expect(SliderTiming.spanDuration(pixelLength: 0, sv: 1, multiplier: 1.4, beatLength: 500) == minimum)
        #expect(SliderTiming.spanDuration(pixelLength: .nan, sv: 1, multiplier: 1.4, beatLength: 500) == minimum)
        #expect(SliderTiming.spanDuration(pixelLength: 100, sv: 0, multiplier: 1.4, beatLength: 500) == minimum)
        #expect(SliderTiming.spanDuration(pixelLength: 100, sv: 1, multiplier: .infinity, beatLength: 500) == minimum)
        #expect(SliderTiming.spanDuration(pixelLength: 100, sv: 1, multiplier: 1.4, beatLength: -1) == minimum)
        #expect(SliderTiming.totalDuration(pixelLength: 100, slides: 0, sv: 1, multiplier: 1, beatLength: 500) > 0)
    }

    @Test("the governing points decide the tempo and SV (S1.6c)")
    func endTime() {
        let points = ControlPoints(
            red: [
                UninheritedTimingPoint(time: 1000, beatLength: 400, meter: 4, kiai: false),
                UninheritedTimingPoint(time: 5000, beatLength: 500, meter: 4, kiai: false),
            ],
            green: [InheritedPoint(time: 1000, sv: 2)],
        )
        let difficulty = BeatmapDifficulty(sliderMultiplier: 1)
        let slider = HitObject.Slider(
            curve: .linear, points: [PlayfieldPoint(x: 100, y: 0)], slides: 2, pixelLength: 100,
        )

        // At 1500: beat 400, SV 2 -> 100/(100*2)*400 = 200 per span, 2 spans.
        let inside = SliderTiming.endTime(of: slider, startTime: 1500, difficulty: difficulty, controlPoints: points)
        #expect(abs(inside - 1900) < 1e-9)

        // Before the first red point osu! reads the first one, not a default.
        let before = SliderTiming.endTime(of: slider, startTime: 0, difficulty: difficulty, controlPoints: points)
        #expect(abs(before - (0 + 2 * (100 / 100.0) * 400)) < 1e-9)

        // A later red resets SV to 1: 100/100*500 = 500 per span.
        let after = SliderTiming.endTime(of: slider, startTime: 6000, difficulty: difficulty, controlPoints: points)
        #expect(abs(after - 7000) < 1e-9)
    }

    @Test("with no timing points the beat length is 500")
    func noPoints() {
        let slider = HitObject.Slider(
            curve: .linear, points: [PlayfieldPoint(x: 140, y: 0)], slides: 1, pixelLength: 140,
        )
        let end = SliderTiming.endTime(
            of: slider, startTime: 100, difficulty: BeatmapDifficulty(sliderMultiplier: 1.4),
            controlPoints: ControlPoints(),
        )
        #expect(abs(end - 600) < 1e-9)
    }
}
