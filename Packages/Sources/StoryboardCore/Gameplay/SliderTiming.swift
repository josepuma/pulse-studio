import Foundation

/// How long a slider lasts: `pixelLength / (multiplier * 100 * sv) * beatLength`
/// per pass, times the number of slides.
public enum SliderTiming {
    /// What a slider with unusable numbers lasts, so downstream code never
    /// divides by zero or draws an object that never ends.
    public static let minimumSpanDuration: Double = 1

    public static func spanDuration(pixelLength: Double, sv: Double, multiplier: Double, beatLength: Double) -> Double {
        guard pixelLength.isFinite, sv.isFinite, multiplier.isFinite, beatLength.isFinite,
              pixelLength > 0, sv > 0, multiplier > 0, beatLength > 0
        else { return minimumSpanDuration }
        let span = pixelLength / (multiplier * 100 * sv) * beatLength
        return span.isFinite ? max(span, minimumSpanDuration) : minimumSpanDuration
    }

    public static func totalDuration(
        pixelLength: Double, slides: Int, sv: Double, multiplier: Double, beatLength: Double,
    ) -> Double {
        let span = spanDuration(pixelLength: pixelLength, sv: sv, multiplier: multiplier, beatLength: beatLength)
        return span * Double(max(1, min(slides, OsuGameplayParser.maxSlides)))
    }

    /// When a slider that starts at `startTime` ends, under the red and green
    /// points that govern that instant.
    public static func endTime(
        of slider: HitObject.Slider,
        startTime: Double,
        difficulty: BeatmapDifficulty,
        controlPoints: ControlPoints,
    ) -> Double {
        startTime + totalDuration(
            pixelLength: slider.pixelLength,
            slides: slider.slides,
            sv: controlPoints.sv(at: startTime),
            multiplier: difficulty.sliderMultiplier,
            beatLength: controlPoints.beatLength(at: startTime),
        )
    }
}
