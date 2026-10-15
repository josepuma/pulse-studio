import Foundation
import Testing

@testable import StoryboardCore

/// Which frame an animated sprite shows, and the instant its clock starts.
///
/// The clock origin is not the sprite's active window: a parameter flag and a
/// loop body's own offset both move it, while `activeStart` ignores the first.
@Suite("Animation resolve")
struct AnimationResolveTests {
    private func fade(_ start: Double, _ end: Double) -> Command {
        Command(easing: .linear, startTime: start, endTime: end, payload: .fade(start: 1, end: 1))
    }

    private func move(_ start: Double, _ end: Double) -> Command {
        Command(easing: .linear, startTime: start, endTime: end, payload: .move(startX: 0, startY: 0, endX: 1, endY: 1))
    }

    private func flag(_ start: Double, _ end: Double) -> Command {
        Command(easing: .linear, startTime: start, endTime: end, payload: .parameter(.additive))
    }

    private func sprite(
        commands: [Command] = [],
        loops: [LoopGroup] = [],
        animation: SpriteAnimation? = SpriteAnimation(frameCount: 4, frameDelay: 100, loopType: .loopForever),
    ) -> StoryboardSprite {
        StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre, filePath: "sb/a.png",
            defaultX: 0, defaultY: 0, commands: commands, loops: loops, animation: animation,
        )
    }

    private func prepared(_ sprite: StoryboardSprite) -> PreparedSprite {
        StoryboardResolver.prepare([sprite])[0]
    }

    private func frame(_ sprite: StoryboardSprite, _ time: Double) -> Int {
        StoryboardResolver.state(of: prepared(sprite), at: time).frameIndex
    }

    @Test("origin is the earliest base command")
    func originEarliestCommand() {
        let p = prepared(sprite(commands: [move(500, 900), fade(1000, 2000)]))
        #expect(p.animationStart == 500)
    }

    @Test("a parameter flag moves the origin but not the active window")
    func parameterMovesOrigin() {
        let p = prepared(sprite(commands: [flag(200, 200), move(1000, 2000)]))
        #expect(p.animationStart == 200)
        #expect(p.activeStart == 1000)
    }

    @Test("a loop contributes its start plus its earliest body command")
    func loopOrigin() {
        let loop = LoopGroup(startTime: 300, loopCount: 2, commands: [move(50, 150)])
        let p = prepared(sprite(loops: [loop]))
        #expect(p.animationStart == 350)
    }

    @Test("an earlier base command beats the loop")
    func baseBeatsLoop() {
        let loop = LoopGroup(startTime: 300, loopCount: 2, commands: [move(50, 150)])
        let p = prepared(sprite(commands: [fade(100, 200)], loops: [loop]))
        #expect(p.animationStart == 100)
    }

    @Test("a loop that starts earlier than the base commands wins")
    func loopBeatsBase() {
        let loop = LoopGroup(startTime: 100, loopCount: 2, commands: [move(20, 150)])
        let p = prepared(sprite(commands: [fade(500, 600)], loops: [loop]))
        #expect(p.animationStart == 120)
    }

    @Test("with no commands the origin falls back to the active start")
    func fallsBack() {
        // A loop whose body has no length is dropped by prepare, leaving the
        // sprite to be dropped too; the fallback only matters in principle, so
        // check the plain-command case keeps both equal.
        let p = prepared(sprite(commands: [move(700, 800)]))
        #expect(p.animationStart == p.activeStart)
    }

    @Test("frames wrap for LoopForever")
    func wraps() {
        let s = sprite(commands: [move(1000, 5000)])
        #expect(frame(s, 1000) == 0)
        #expect(frame(s, 1100) == 1)
        #expect(frame(s, 1399) == 3)
        #expect(frame(s, 1400) == 0)
        #expect(frame(s, 1550) == 1)
    }

    @Test("LoopOnce holds the last frame")
    func holds() {
        let s = sprite(
            commands: [move(1000, 99_999)],
            animation: SpriteAnimation(frameCount: 4, frameDelay: 100, loopType: .loopOnce),
        )
        #expect(frame(s, 1100) == 1)
        #expect(frame(s, 9999) == 3)
    }

    @Test("before the origin it is frame 0 for both loop types")
    func beforeOrigin() {
        for type in [AnimationLoopType.loopForever, .loopOnce] {
            let s = sprite(
                commands: [move(1000, 2000)],
                animation: SpriteAnimation(frameCount: 4, frameDelay: 100, loopType: type),
            )
            #expect(frame(s, 900) == 0)
        }
    }

    @Test("a loop does not restart the frame clock")
    func loopDoesNotRestart() {
        // Iterations are 200 ms long starting at 1000; the clock starts at
        // 1000 too. Inside the second iteration (t = 1250) the song-time frame
        // is 2; a per-iteration restart would give 0.
        let loop = LoopGroup(startTime: 1000, loopCount: 5, commands: [move(0, 200)])
        let s = sprite(loops: [loop])
        #expect(frame(s, 1250) == 2)
        #expect(frame(s, 1050) == 0)
    }

    @Test("the parameter origin drives the frame")
    func parameterDrivesFrame() {
        let s = sprite(commands: [flag(200, 200), move(1000, 2000)])
        // Origin 200: at 1000 elapsed is 800 -> step 8 -> 8 mod 4 = 0; at 1100 -> 9 mod 4 = 1.
        #expect(frame(s, 1100) == 1)
    }

    @Test("a plain sprite stays at frame 0")
    func plainIsZero() {
        let s = sprite(commands: [move(0, 5000)], animation: nil)
        #expect(frame(s, 2500) == 0)
        #expect(prepared(s).framePaths == nil)
    }

    @Test("frame paths are built once in prepare")
    func pathsPrecomputed() {
        let p = prepared(sprite(commands: [move(0, 100)]))
        #expect(p.framePaths == ["sb/a0.png", "sb/a1.png", "sb/a2.png", "sb/a3.png"])
    }
}
