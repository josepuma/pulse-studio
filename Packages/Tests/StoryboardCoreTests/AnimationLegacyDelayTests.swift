import Foundation
import Testing

@testable import StoryboardCore

/// The frame delay an old map's animations really play at.
///
/// Reported against a real map (set 5381, every difficulty v5): its animations
/// played about three and a half times slower in the editor than in the game.
/// The game reads the `.osb` with the version of the `.osu` it belongs to, and
/// for files older than v6 it requantises every frame delay. The file keeps
/// the value as written; only playback uses the adjusted one.
@Suite("Animation legacy frame delay")
struct AnimationLegacyDelayTests {
    /// 1000 / 60 as the game computes it, in single precision.
    private static let tick = Double(Float(1000) / Float(60))

    @Test("old files snap the delay to the game's legacy ticks")
    func oldFormatAdjusts() {
        let delay = AnimationFrames.playbackDelay(400, formatVersion: 5)
        #expect(abs(delay - 6 * 1.186 * Self.tick) < 1e-9)
        // About 118.6 ms — the speed the game showed.
        #expect(abs(delay - 118.6) < 0.01)
    }

    @Test("an exact half rounds to the even neighbour")
    func halfRoundsToEven() {
        // 0.015 × 300 is exactly 4.5: rounding away from zero would give 5.
        let delay = AnimationFrames.playbackDelay(300, formatVersion: 5)
        #expect(abs(delay - 4 * 1.186 * Self.tick) < 1e-9)
    }

    @Test("v6 and later play the delay as written")
    func newFormatUnchanged() {
        #expect(AnimationFrames.playbackDelay(400, formatVersion: 6) == 400)
        #expect(AnimationFrames.playbackDelay(400, formatVersion: 14) == 400)
    }

    @Test("no known version plays the delay as written")
    func unknownVersionUnchanged() {
        #expect(AnimationFrames.playbackDelay(400, formatVersion: nil) == 400)
    }

    @Test("the frame clock uses the playback delay, not the written one")
    func indexUsesPlaybackDelay() {
        var animation = SpriteAnimation(frameCount: 4, frameDelay: 400, loopType: .loopForever)
        animation.playbackFrameDelay = 100
        #expect(AnimationFrames.index(at: 150, origin: 0, animation: animation) == 1)
        #expect(AnimationFrames.index(at: 350, origin: 0, animation: animation) == 3)

        animation.playbackFrameDelay = nil
        #expect(AnimationFrames.index(at: 350, origin: 0, animation: animation) == 0)
    }

    @Test("the writer keeps the delay as it was written")
    func writerKeepsRawDelay() {
        var animation = SpriteAnimation(frameCount: 2, frameDelay: 400, loopType: .loopForever)
        animation.playbackFrameDelay = 118.6
        let sprite = StoryboardSprite(
            id: "s", layer: .background, origin: .topLeft, filePath: "bg/go.png",
            defaultX: 0, defaultY: 0, animation: animation,
        )
        let text = OsbWriter.write([sprite])
        #expect(text.contains("Animation,Background,TopLeft,\"bg/go.png\",0,0,2,400,LoopForever"))
    }

    // ─── Reading the version ────────────────────────────────────────────────

    @Test("reads the version from the header")
    func parsesVersion() {
        #expect(OsuFormatVersion.parse("osu file format v5\n\n[General]\n") == 5)
        #expect(OsuFormatVersion.parse("osu file format v14\r\n[General]") == 14)
    }

    @Test("tolerates a BOM and blank lines before the header")
    func toleratesBOM() {
        #expect(OsuFormatVersion.parse("\u{FEFF}\n  osu file format v7\n") == 7)
    }

    @Test("no header, or a garbled one, is no version")
    func missingVersion() {
        #expect(OsuFormatVersion.parse("[General]\nAudioFilename: a.mp3") == nil)
        #expect(OsuFormatVersion.parse("osu file format vX") == nil)
        #expect(OsuFormatVersion.parse("") == nil)
        // Only the first line counts: a later mention is not the header.
        #expect(OsuFormatVersion.parse("[General]\nosu file format v5") == nil)
    }
}
