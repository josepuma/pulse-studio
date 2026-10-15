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

    /// Which frame shows at `time`, given the instant the animation's clock
    /// started. Before that instant it is frame 0 for both loop types.
    public static func index(at time: Double, origin: Double, animation: SpriteAnimation) -> Int {
        let count = min(max(animation.frameCount, 1), maximumFrameCount)
        let elapsed = time - origin
        guard elapsed >= 0, animation.frameDelay > 0, elapsed.isFinite else { return 0 }

        // Kept in Double until the result is known to be small: converting a
        // huge quotient to Int traps.
        let steps = (elapsed / animation.frameDelay).rounded(.down)
        switch animation.loopType {
        case .loopForever:
            return Int(steps.truncatingRemainder(dividingBy: Double(count)))
        case .loopOnce:
            return Int(min(steps, Double(count - 1)))
        }
    }
}
