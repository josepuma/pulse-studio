/// What an `Animation` header adds to a sprite: a numbered run of frame files
/// and how fast and how often they cycle.
public enum AnimationLoopType: String, Sendable {
    case loopForever = "LoopForever"
    case loopOnce = "LoopOnce"

    /// Anything unrecognised cycles forever, the way osu! reads a header whose
    /// last field is missing or misspelled.
    public init(osbName: String) {
        self = AnimationLoopType(rawValue: osbName) ?? .loopForever
    }
}

/// Frame data of an animated sprite. `nil` on a sprite means it is plain.
public struct SpriteAnimation: Sendable, Equatable {
    public var frameCount: Int
    /// Milliseconds each frame stays on screen.
    public var frameDelay: Double
    public var loopType: AnimationLoopType

    public init(frameCount: Int, frameDelay: Double, loopType: AnimationLoopType) {
        self.frameCount = frameCount
        self.frameDelay = frameDelay
        self.loopType = loopType
    }
}
