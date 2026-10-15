import Testing

@testable import StoryboardCore

@Suite("AnimationFrames")
struct AnimationFramesTests {
    private func animation(
        count: Int = 4, delay: Double = 100, loop: AnimationLoopType = .loopForever,
    ) -> SpriteAnimation {
        SpriteAnimation(frameCount: count, frameDelay: delay, loopType: loop)
    }

    // ─── Frame path ──────────────────────────────────────────────────────────

    @Test("the frame number goes before every dot")
    func pathInsertsIndexBeforeEveryDot() {
        #expect(AnimationFrames.path(base: "sb/a.png", frame: 2) == "sb/a2.png")
        #expect(AnimationFrames.path(base: "sb/a.png", frame: 0) == "sb/a0.png")
        #expect(AnimationFrames.path(base: "a.b.png", frame: 1) == "a1.b1.png")
    }

    @Test("a path without a dot is left alone")
    func pathWithoutDot() {
        #expect(AnimationFrames.path(base: "sb/frame", frame: 3) == "sb/frame")
    }

    // ─── Frame index ─────────────────────────────────────────────────────────

    @Test("forever wraps around the frame count")
    func foreverWraps() {
        let a = animation()
        #expect(AnimationFrames.index(at: 1000, origin: 1000, animation: a) == 0)
        #expect(AnimationFrames.index(at: 1100, origin: 1000, animation: a) == 1)
        #expect(AnimationFrames.index(at: 1399, origin: 1000, animation: a) == 3)
        #expect(AnimationFrames.index(at: 1400, origin: 1000, animation: a) == 0)
        #expect(AnimationFrames.index(at: 1550, origin: 1000, animation: a) == 1)
    }

    @Test("once holds the last frame")
    func onceClamps() {
        let a = animation(loop: .loopOnce)
        #expect(AnimationFrames.index(at: 9999, origin: 1000, animation: a) == 3)
        #expect(AnimationFrames.index(at: 1200, origin: 1000, animation: a) == 2)
    }

    @Test("before the clock origin both loop types show frame 0")
    func negativeElapsedIsFrameZero() {
        for loop in [AnimationLoopType.loopForever, .loopOnce] {
            let a = animation(loop: loop)
            #expect(AnimationFrames.index(at: 900, origin: 1000, animation: a) == 0)
            // Just below zero elapsed: a truncating division would round this up to 0
            // and a negative remainder would index backwards.
            #expect(AnimationFrames.index(at: 950, origin: 1000, animation: a) == 0)
            #expect(AnimationFrames.index(at: -1e9, origin: 1000, animation: a) == 0)
        }
    }

    // ─── Path lists ──────────────────────────────────────────────────────────

    @Test("the frame count is capped")
    func countIsClamped() {
        let hostile = animation(count: 100_000)
        let paths = AnimationFrames.paths(base: "sb/a.png", animation: hostile)
        #expect(AnimationFrames.maximumFrameCount == 4096)
        #expect(paths.count == AnimationFrames.maximumFrameCount)
        #expect(paths.first == "sb/a0.png")
        #expect(paths.last == "sb/a4095.png")
    }

    @Test("a plain sprite names only its own file, an animated one every frame")
    func pathsOfSprite() {
        var sprite = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre, filePath: "sb/f.png", defaultX: 0, defaultY: 0,
        )
        #expect(AnimationFrames.paths(of: sprite) == ["sb/f.png"])

        sprite.animation = animation(count: 3)
        #expect(AnimationFrames.paths(of: sprite) == ["sb/f0.png", "sb/f1.png", "sb/f2.png"])
    }

    @Test("a plain sprite carries no animation")
    func plainSpriteHasNone() {
        let sprite = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre, filePath: "x.png", defaultX: 0, defaultY: 0,
        )
        #expect(sprite.animation == nil)
    }

    @Test("an unknown loop type name means forever")
    func unknownLoopName() {
        #expect(AnimationLoopType(osbName: "LoopOnce") == .loopOnce)
        #expect(AnimationLoopType(osbName: "LoopForever") == .loopForever)
        #expect(AnimationLoopType(osbName: "Bogus") == .loopForever)
        #expect(AnimationLoopType(osbName: "") == .loopForever)
    }
}
