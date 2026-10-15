import Testing

import StoryboardCore
@testable import StoryboardRendering

/// Which image an animated sprite draws, and which images the atlas must hold.
///
/// Pure selection logic: the GPU only consumes the answer, so CI covers it
/// without a device.
@Suite("Animation frame textures")
struct AnimationFrameTextureTests {
    private func prepared(
        _ id: String = "s",
        path: String = "sb/a.png",
        animation: SpriteAnimation? = SpriteAnimation(frameCount: 3, frameDelay: 100, loopType: .loopForever),
    ) -> PreparedSprite {
        let sprite = StoryboardSprite(
            id: id, layer: .foreground, origin: .centre, filePath: path,
            defaultX: 0, defaultY: 0,
            commands: [Command(easing: .linear, startTime: 0, endTime: 1000, payload: .fade(start: 1, end: 1))],
            animation: animation,
        )
        return StoryboardResolver.prepare([sprite])[0]
    }

    @Test("the current frame picks its own file")
    func currentFramePath() {
        let sprite = prepared()
        #expect(FrameTextures.path(for: sprite, frameIndex: 0) == "sb/a0.png")
        #expect(FrameTextures.path(for: sprite, frameIndex: 2) == "sb/a2.png")
    }

    @Test("a plain sprite always uses its own path, and a stray index is safe")
    func plainAndOutOfRange() {
        #expect(FrameTextures.path(for: prepared(animation: nil), frameIndex: 5) == "sb/a.png")
        #expect(FrameTextures.path(for: prepared(), frameIndex: 99) == "sb/a.png")
        #expect(FrameTextures.path(for: prepared(), frameIndex: -1) == "sb/a.png")
    }

    @Test("the atlas holds every frame, the base path only for plain sprites")
    func atlasUnion() {
        let paths = FrameTextures.atlasPaths(for: [
            prepared("a"),
            prepared("b", path: "sb/plain.png", animation: nil),
            prepared("c"),
        ])
        #expect(paths == ["sb/a0.png", "sb/a1.png", "sb/a2.png", "sb/plain.png"])
    }

    /// Frames of different sizes must each report their own pixel size and
    /// alpha mask: the entry is looked up by the current frame's path.
    @Test("each frame reads its own entry")
    func ownEntryPerFrame() {
        let sprite = prepared()
        let entries = ["sb/a0.png": 64, "sb/a1.png": 128]
        #expect(FrameTextures.entry(for: sprite, frameIndex: 0, in: entries) == 64)
        #expect(FrameTextures.entry(for: sprite, frameIndex: 1, in: entries) == 128)
    }

    @Test("a missing frame has no entry, so it draws the flat quad")
    func missingFrame() {
        let sprite = prepared()
        let entries = ["sb/a0.png": 64]
        #expect(FrameTextures.entry(for: sprite, frameIndex: 1, in: entries) == nil)
        // The base path is not a fallback: it is not an image of the animation.
        #expect(FrameTextures.entry(for: sprite, frameIndex: 2, in: ["sb/a.png": 7]) == nil)
    }
}
