@testable import StoryboardCore

/// Builds gameplay subjects the way the loader would hand them over: a parsed
/// `BeatmapGameplay` with difficulty and control points, not hand-made structs.
enum GameplayFixture {
    static let red = UninheritedTimingPoint(time: 0, beatLength: 500, meter: 4, kiai: false)

    static func gameplay(
        ar: Double = 9,
        cs: Double = 4,
        objects: [HitObject],
        green: [InheritedPoint] = [],
    ) -> BeatmapGameplay {
        BeatmapGameplay(
            difficulty: BeatmapDifficulty(hp: 5, cs: cs, od: 5, ar: ar, sliderMultiplier: 1.4, sliderTickRate: 1),
            controlPoints: ControlPoints(red: [red], green: green),
            hitObjects: objects,
        )
    }

    static func circle(at time: Double, x: Double = 256, y: Double = 192, combo: Int = 1) -> HitObject {
        HitObject(time: time, position: PlayfieldPoint(x: x, y: y), comboNumber: combo, kind: .circle)
    }

    /// 140px at multiplier 1.4, SV 1 and 500ms beats lasts 500ms per slide.
    static func slider(
        at time: Double, slides: Int = 1, curve: CurveType = .linear,
        head: PlayfieldPoint = PlayfieldPoint(x: 100, y: 100),
        tail: PlayfieldPoint = PlayfieldPoint(x: 240, y: 100), pixelLength: Double = 140,
    ) -> HitObject {
        HitObject(
            time: time, position: head,
            kind: .slider(.init(curve: curve, points: [tail], slides: slides, pixelLength: pixelLength)),
        )
    }

    static func spinner(from time: Double, to end: Double) -> HitObject {
        HitObject(time: time, position: PlayfieldPoint(x: 256, y: 192), kind: .spinner(endTime: end))
    }
}
