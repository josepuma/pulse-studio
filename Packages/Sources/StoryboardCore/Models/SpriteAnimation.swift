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
    /// The delay the game actually plays, when it differs from the written one.
    ///
    /// Maps older than v6 have their frame delays requantised on load
    /// (``AnimationFrames/playbackDelay(_:formatVersion:)``), and the `.osb`
    /// takes the version of the `.osu` it is read with. Kept apart from
    /// `frameDelay` so the file round-trips with the value it was written with:
    /// `nil` plays `frameDelay` as is.
    public var playbackFrameDelay: Double?

    public init(
        frameCount: Int,
        frameDelay: Double,
        loopType: AnimationLoopType,
        playbackFrameDelay: Double? = nil,
    ) {
        self.frameCount = frameCount
        self.frameDelay = frameDelay
        self.loopType = loopType
        self.playbackFrameDelay = playbackFrameDelay
    }
}
