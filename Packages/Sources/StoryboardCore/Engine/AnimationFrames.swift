import Foundation

/// The rules that turn an `Animation` header into files and a frame number.
///
/// Pure on purpose: the resolver, the renderer, the loader and the export all
/// need the same answers, and none of them should re-derive a path rule.
public enum AnimationFrames {
    /// Most frames one sprite may name. The count comes from a file somebody
    /// else wrote, and every frame is a path to read and an atlas entry.
    public static let maximumFrameCount = 4096

    /// Frame files are the base name with the frame number put before each dot,
    /// counting from 0: `sb/a.png` becomes `sb/a2.png` for frame 2. Every dot
    /// gets it, so `a.b.png` becomes `a1.b1.png`. A name with no dot has no
    /// place to put a number and stays as it is.
    public static func path(base: String, frame: Int) -> String {
        base.replacingOccurrences(of: ".", with: "\(frame).")
    }

    /// Every frame file, with the count held to `maximumFrameCount`.
    public static func paths(base: String, animation: SpriteAnimation) -> [String] {
        let count = min(max(animation.frameCount, 0), maximumFrameCount)
        return (0..<count).map { path(base: base, frame: $0) }
    }

    /// The files a sprite needs: its own for a plain one, all its frames otherwise.
    public static func paths(of sprite: StoryboardSprite) -> [String] {
        guard let animation = sprite.animation else { return [sprite.filePath] }
        return paths(base: sprite.filePath, animation: animation)
    }

    /// The frame delay the game plays for a file of a given format version.
    ///
    /// Files older than v6 come from a time when the game counted animation
    /// frames in its own coarse ticks, and it still converts those delays on
    /// load: scaled by 0.015 and rounded to a whole number — an exact half goes
    /// to the even neighbour — then multiplied by 1.186 and by 1000/60 taken in
    /// single precision. A 400 ms delay plays at about 118.6 ms. Newer files,
    /// and a delay with no known version, play as written.
    public static func playbackDelay(_ delay: Double, formatVersion: Int?) -> Double {
        guard let formatVersion, formatVersion < 6 else { return delay }
        let ticks = (0.015 * delay).rounded(.toNearestOrEven)
        return ticks * 1.186 * Double(Float(1000) / Float(60))
    }

    /// Which frame shows at `time`, given the instant the animation's clock
    /// started. Before that instant it is frame 0 for both loop types.
    public static func index(at time: Double, origin: Double, animation: SpriteAnimation) -> Int {
        let count = min(max(animation.frameCount, 1), maximumFrameCount)
        let delay = animation.playbackFrameDelay ?? animation.frameDelay
        let elapsed = time - origin
        guard elapsed >= 0, delay > 0, elapsed.isFinite else { return 0 }

        // Kept in Double until the result is known to be small: converting a
        // huge quotient to Int traps.
        let steps = (elapsed / delay).rounded(.down)
        switch animation.loopType {
        case .loopForever:
            return Int(steps.truncatingRemainder(dividingBy: Double(count)))
        case .loopOnce:
            return Int(min(steps, Double(count - 1)))
        }
    }
}

// ─── What a prepared sprite draws ───────────────────────────────────────────

extension PreparedSprite {
    /// Every image file this sprite can draw: all its frames when animated,
    /// otherwise its one path. The base path of an animation is not an image
    /// of it, so it is absent here.
    public var texturePaths: [String] { framePaths ?? [filePath] }

    /// The image for a given frame, by subscript — no string is built per frame.
    /// A stray index falls back to the base path, which has no entry for an
    /// animation and so draws the flat quad rather than the wrong picture.
    public func texturePath(frameIndex: Int) -> String {
        guard let framePaths, framePaths.indices.contains(frameIndex) else { return filePath }
        return framePaths[frameIndex]
    }
}
