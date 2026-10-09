import Foundation

/// What to draw for one object at one instant. Pure instance data: positions
/// are already in storyboard space and nothing here knows about the GPU.
public struct ObjectVisual: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case circle, slider, spinner }

    public struct ReverseArrow: Sendable, Equatable {
        public var position: PlayfieldPoint
        /// Radians in storyboard space, pointing the way the ball will go back.
        public var angle: Double
    }

    /// Position of the object in `GameplayMap.objects`.
    public var objectIndex: Int
    public var kind: Kind
    /// Where the circle / slider head / spinner centre is.
    public var position: PlayfieldPoint
    public var radius: Double
    /// Opacity of the body.
    public var alpha: Double
    /// Approach circle size as a multiple of `radius` (4 → 1), and its opacity
    /// (0 once the object has been hit).
    public var approachScale: Double
    public var approachAlpha: Double
    public var comboNumber: Int
    /// The slider ball while it is travelling.
    public var ball: PlayfieldPoint?
    public var reverseArrows: [ReverseArrow]
    /// 0...1 over a spinner's life; `nil` for other kinds.
    public var spinnerProgress: Double?
}

/// Turns a map and a time into the objects on screen, latest first.
public enum GameplayFrame {
    /// A spinner fills the playfield height.
    public static let spinnerRadius: Double = 192
    /// Times past this cannot match any object and would only invite overflow.
    private static let timeLimit: Double = 1e8

    /// Latest object first: osu! draws earlier objects on top of later ones,
    /// so painting back to front means the earliest lands last. UNVERIFIED
    /// against a stable capture (task 3.1 is still open).
    public static func build(_ map: GameplayMap, at time: Double) -> [ObjectVisual] {
        guard time.isFinite, abs(time) <= timeLimit else { return [] }
        return map.index.candidates(at: time).reversed().map { visual(map, map.objects[$0], at: time) }
    }

    private static func visual(_ map: GameplayMap, _ placed: PlacedObject, at time: Double) -> ObjectVisual {
        let object = placed.object
        let fadeIn = BeatmapDifficultyMath.fadeIn(preempt: placed.preempt)
        let appeared = fadeIn > 0 ? min(max((time - placed.visibleStart) / fadeIn, 0), 1) : 1
        let faded = time > placed.endTime ? 1 - min((time - placed.endTime) / GameplayMap.fadeOut, 1) : 1
        let toHit = object.time - time

        var visual = ObjectVisual(
            objectIndex: placed.index,
            kind: .circle,
            position: PlayfieldMapping.storyboard(object.position),
            radius: placed.radius,
            alpha: appeared * faded,
            approachScale: BeatmapDifficultyMath.approachScale(timeBeforeHit: toHit, preempt: placed.preempt),
            approachAlpha: toHit > 0 ? appeared : 0,
            comboNumber: object.comboNumber,
            ball: nil,
            reverseArrows: [],
            spinnerProgress: nil,
        )

        switch object.kind {
        case .circle:
            break
        case let .spinner(endTime):
            visual.kind = .spinner
            visual.radius = spinnerRadius
            visual.approachAlpha = 0
            let length = max(endTime - object.time, 1)
            visual.spinnerProgress = min(max((time - object.time) / length, 0), 1)
        case let .slider(slider):
            visual.kind = .slider
            guard let path = map.path(forObject: placed.index, at: time) else { break }
            let slides = max(1, slider.slides)
            let span = max(placed.spanDuration, SliderTiming.minimumSpanDuration)
            let progress = min(max((time - object.time) / span, 0), Double(slides))
            if time >= object.time, time <= placed.endTime {
                visual.ball = PlayfieldMapping.storyboard(path.position(at: progress, slides: slides))
            }
            visual.reverseArrows = reverseArrows(path: path, slides: slides, progress: progress, ended: time > placed.endTime)
        }
        return visual
    }

    /// The reversal after pass `b` (0-based) happens at the tail when `b` is
    /// even and at the head when it is odd. One is shown while it still lies
    /// ahead of the ball.
    private static func reverseArrows(
        path: SliderPath, slides: Int, progress: Double, ended: Bool,
    ) -> [ObjectVisual.ReverseArrow] {
        guard slides > 1, !ended, path.points.count >= 2 else { return [] }
        let currentPass = min(Int(progress.rounded(.down)), slides - 1)
        var tail = false, head = false
        for boundary in max(0, currentPass) ..< (slides - 1) {
            if boundary % 2 == 0 { tail = true } else { head = true }
        }
        var arrows: [ObjectVisual.ReverseArrow] = []
        let points = path.points
        if tail {
            let end = points[points.count - 1], before = points[points.count - 2]
            arrows.append(.init(
                position: PlayfieldMapping.storyboard(end),
                angle: atan2(before.y - end.y, before.x - end.x),
            ))
        }
        if head {
            let start = points[0], after = points[1]
            arrows.append(.init(
                position: PlayfieldMapping.storyboard(start),
                angle: atan2(after.y - start.y, after.x - start.x),
            ))
        }
        return arrows
    }
}
