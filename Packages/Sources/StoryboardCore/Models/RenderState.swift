/// A sprite's fully resolved appearance at one point in time.
///
/// Ported from `SpriteRenderState` in `app/types/renderer.ts`. The TypeScript
/// version is pooled and mutated in place to avoid garbage-collector pressure;
/// as a `struct` this is stack-allocated, so the pool is unnecessary here.
public struct SpriteRenderState: Sendable, Equatable {
    public var spriteId: String
    public var x: Double
    public var y: Double
    public var scaleX: Double
    public var scaleY: Double
    /// Rotation in radians.
    public var rotation: Double
    public var opacity: Double
    /// Colour channels in [0, 255].
    public var r: Double
    public var g: Double
    public var b: Double
    public var visible: Bool
    public var additive: Bool
    public var flipH: Bool
    public var flipV: Bool
    /// Which animation frame shows; always 0 for a plain sprite.
    public var frameIndex: Int

    public init(
        spriteId: String = "",
        x: Double = 0,
        y: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        rotation: Double = 0,
        opacity: Double = 1,
        r: Double = 255,
        g: Double = 255,
        b: Double = 255,
        visible: Bool = true,
        additive: Bool = false,
        flipH: Bool = false,
        flipV: Bool = false,
        frameIndex: Int = 0,
    ) {
        self.spriteId = spriteId
        self.x = x
        self.y = y
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotation = rotation
        self.opacity = opacity
        self.r = r
        self.g = g
        self.b = b
        self.visible = visible
        self.additive = additive
        self.flipH = flipH
        self.flipV = flipV
        self.frameIndex = frameIndex
    }
}
