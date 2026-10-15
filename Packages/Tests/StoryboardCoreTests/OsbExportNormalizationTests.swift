import Foundation
import Testing

@testable import StoryboardCore

/// What the file says has to be what osu! draws, without the preview moving.
///
/// Two disagreements between the editor's resolver and osu! are closed on the
/// way out: `S` and `V` are separate properties in the game (so a stray `S`
/// zeroes a `V` sprite), and a zero-length `P` is momentary there but permanent
/// here. Every check reads the WRITTEN text, and the round-trip ones resolve it
/// again — a normalisation that fixed the file by changing the picture would
/// be its own bug.
@Suite("OSB export normalisation")
struct OsbExportNormalizationTests {
    // ─── Helpers ─────────────────────────────────────────────────────────────

    private func sprite(
        id: String = "s",
        _ commands: [Command],
        loops: [LoopGroup] = [],
    ) -> StoryboardSprite {
        StoryboardSprite(
            id: id, layer: .foreground, origin: .topCentre, filePath: "sb/a.png",
            defaultX: 320, defaultY: 240, commands: commands, loops: loops,
        )
    }

    private func fade(_ start: Double, _ end: Double, _ a: Double = 1, _ b: Double = 1) -> Command {
        Command(easing: .linear, startTime: start, endTime: end, payload: .fade(start: a, end: b))
    }

    private func scale(_ start: Double, _ end: Double, _ a: Double, _ b: Double,
                       easing: Easing = .linear) -> Command {
        Command(easing: easing, startTime: start, endTime: end, payload: .scale(start: a, end: b))
    }

    private func vector(_ start: Double, _ end: Double, _ x: Double, _ y: Double) -> Command {
        Command(easing: .linear, startTime: start, endTime: end,
                payload: .vectorScale(startX: x, startY: y, endX: x, endY: y))
    }

    private func flip(_ time: Double, _ end: Double? = nil, _ kind: ParameterKind = .flipHorizontal) -> Command {
        Command(easing: .linear, startTime: time, endTime: end ?? time, payload: .parameter(kind))
    }

    private func written(_ sprites: [StoryboardSprite]) -> [String] {
        OsbWriter.write(OsbExportNormalization.normalize(sprites))
            .split(separator: "\n").map(String.init)
    }

    private func commandLines(_ lines: [String], _ kind: String) -> [String] {
        lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix(kind + ",") }
    }

    private func resolved(_ sprites: [StoryboardSprite], at time: Double) -> SpriteRenderState? {
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: time, into: &states)
        return states.first
    }

    // ─── S → V ───────────────────────────────────────────────────────────────

    /// The exact shape from the real export: a held `S 0,0` ahead of a pop-in
    /// written as `V`. osu! combined them and drew nothing.
    @Test("a sprite with a V has no S left, and the V lines carry (s, s)")
    func strayScaleBecomesVector() {
        let lines = written([sprite([
            fade(0, 5000),
            scale(36481, 36500, 0, 0),
            scale(36600, 36700, 0.5, 2, easing: .quadOut),
            vector(36500, 36513, 0.048, 0.297),
        ])])

        #expect(commandLines(lines, "S").isEmpty, "an S survived: \(lines)")
        let vectors = commandLines(lines, "V")
        #expect(vectors.contains { $0.contains(",36481,36500,0,0,0,0") }, "\(vectors)")
        // Same times, same easing (quadOut is 5's neighbour — read from the enum).
        let eased = "V,\(Easing.quadOut.rawValue),36600,36700,0.500,0.500,2,2"
        #expect(vectors.contains { $0.trimmingCharacters(in: .whitespaces) == eased }, "\(vectors)")
    }

    /// The uniform form is cheaper, and a sprite that never touches `V` has no
    /// reason to pay for it.
    @Test("a sprite with only S keeps S")
    func onlyScaleIsUntouched() {
        let lines = written([sprite([fade(0, 100), scale(0, 100, 0.5, 1)])])
        #expect(commandLines(lines, "S").count == 1)
        #expect(commandLines(lines, "V").isEmpty)
    }

    /// osu! combines the two properties across the whole sprite, so a `V` that
    /// lives only inside a loop body still makes the outer `S` dangerous.
    @Test("a V inside a loop body counts")
    func vectorInLoopCounts() {
        let lines = written([sprite(
            [fade(0, 1000), scale(0, 100, 0, 0)],
            loops: [LoopGroup(startTime: 100, loopCount: 3, commands: [
                vector(0, 200, 1, 2), scale(200, 300, 1, 1),
            ])],
        )])

        #expect(commandLines(lines, "S").isEmpty, "\(lines)")
        #expect(commandLines(lines, "V").count == 3)
    }

    // ─── P ───────────────────────────────────────────────────────────────────

    @Test("a zero-length P runs to the sprite's death")
    func zeroLengthParameterHolds() {
        let lines = written([sprite([fade(0, 3000), flip(500)])])
        let p = commandLines(lines, "P")
        #expect(p == [" P,0,500,3000,H"], "\(p)")
    }

    /// Death is the resolver's own answer, loops included: start + count × period.
    @Test("death counts a loop's whole run")
    func deathCountsLoops() {
        let lines = written([sprite(
            [fade(0, 1000), flip(0)],
            loops: [LoopGroup(startTime: 1000, loopCount: 4, commands: [fade(0, 500)])],
        )])
        #expect(commandLines(lines, "P") == [" P,0,0,3000,H"], "\(lines)")
    }

    @Test("a P that already has a length is left alone")
    func nonZeroParameterUntouched() {
        // Beside an instant one, so the sprite is normalised at all — a sprite
        // with nothing to fix is returned untouched and would prove nothing.
        let lines = written([sprite([fade(0, 3000), flip(500, 900, .additive), flip(700)])])
        #expect(commandLines(lines, "P") == [" P,0,500,900,A", " P,0,700,3000,H"])
    }

    /// Inside a loop the body is relative to each iteration, so the hold ends
    /// with THAT iteration rather than with the sprite — otherwise the flag
    /// would outlive its own pass and leak into the next.
    @Test("a P in a loop body holds to the end of the iteration")
    func loopParameterHoldsToIteration() {
        let lines = written([sprite(
            [fade(0, 5000)],
            loops: [LoopGroup(startTime: 1000, loopCount: 3, commands: [
                fade(0, 800), flip(100),
            ])],
        )])
        #expect(commandLines(lines, "P") == ["  P,0,100,800,H"], "\(lines)")
    }

    // ─── The preview does not move ───────────────────────────────────────────

    /// Written, parsed back and resolved by the editor's own resolver: the
    /// states must equal the ones the pre-export sprites give. The file changes;
    /// the picture does not.
    ///
    /// Over the real pattern — an `S` hold that equals the `V`'s first value,
    /// a pop-in from zero. The resolver lets a sprite's `V` track override its
    /// `S` track outright (even before the first `V` starts, it holds that
    /// command's start value), so an `S` that DISAGREES with the `V` was dead
    /// in the preview and is live in the file: there the file shows what osu!
    /// shows, and the two intentionally differ.
    @Test("normalising does not change what the resolver draws")
    func roundTripKeepsThePicture() {
        let sprites = [
            sprite([
                fade(0, 4000),
                scale(0, 500, 0, 0),
                Command(easing: .linear, startTime: 500, endTime: 900,
                        payload: .vectorScale(startX: 0, startY: 0, endX: 0.2, endY: 0.4)),
                flip(300),
                flip(700, 1200, .additive),
            ]),
            sprite(
                [fade(0, 6000), scale(0, 200, 1, 1)],
                loops: [LoopGroup(startTime: 1000, loopCount: 3, commands: [
                    fade(0, 800), vector(0, 400, 1, 1), flip(50, nil, .flipVertical),
                ])],
            ),
        ]

        let parsed = OsbParser.parse(OsbWriter.write(OsbExportNormalization.normalize(sprites))).sprites
        #expect(parsed.count == sprites.count)

        for time in stride(from: 0.0, through: 6000, by: 125) {
            var before: [SpriteRenderState] = []
            var after: [SpriteRenderState] = []
            StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: time, into: &before)
            StoryboardResolver.resolve(StoryboardResolver.prepare(parsed), at: time, into: &after)

            #expect(before.count == after.count, "live count differs at \(time)")
            for (a, b) in zip(before, after) {
                var b = b
                b.spriteId = a.spriteId
                #expect(a == b, "the picture moved at \(time): \(a) vs \(b)")
            }
        }
    }

    // ─── Through the real pipeline ───────────────────────────────────────────

    /// The bug from the export: a Mirror copy's flip is a zero-length P, which
    /// osu! applies for an instant.
    @Test("a mirrored shape's copy has a P spanning its life")
    func mirrorCopyFlipSpansItsLife() throws {
        var document = EffectDocument()
        let node = document.add(ShapeEffect.descriptor, at: 1000, duration: 4000)
        let filter = document.addFilter(MirrorFilter.descriptor, to: node.id)
        try #require(filter != nil)

        let sprites = EffectEvaluator().evaluate(document)
        // Evidence the premise holds: the evaluator really does emit the instant P.
        #expect(sprites.contains { $0.commands.contains { $0.kind == .parameter && $0.startTime == $0.endTime } },
                "the mirror no longer writes a zero-length P — this test lost its premise")

        let lines = written(sprites)
        let flips = commandLines(lines, "P")
        #expect(!flips.isEmpty)
        for line in flips {
            let fields = line.trimmingCharacters(in: .whitespaces).split(separator: ",", omittingEmptySubsequences: false)
            #expect(fields[3] != "", "a P is still written as an instant: \(line)")
            let start = try #require(Double(fields[2]))
            let end = try #require(Double(fields[3]))
            #expect(end - start >= 3999, "the flip does not span the sprite's life: \(line)")
        }
    }

    /// The stray S from a camera bake over a `V` sprite never reaches the file.
    @Test("a camera bake over a V sprite exports without S")
    func cameraStrayScaleIsGone() {
        var camera = StoryboardCamera()
        camera[.zoom] = KeyframeTrack([
            Keyframe(time: 0, value: 1, easing: .linear),
            Keyframe(time: 2000, value: 2, easing: .linear),
        ])
        // The real pattern: a pop-in from (0, 0). Before it starts the
        // resolver holds the first V's start value — equal axes — so the bake
        // writes that stretch as an S beside the V that follows.
        let base = sprite([
            fade(0, 2000),
            Command(easing: .linear, startTime: 500, endTime: 1500,
                    payload: .vectorScale(startX: 0, startY: 0, endX: 0.3, endY: 0.6)),
        ])
        let baked = CameraTransform.apply(camera, to: [base])

        #expect(baked.flatMap(\.commands).contains { $0.kind == .vectorScale })
        #expect(baked.flatMap(\.commands).contains { $0.kind == .scale },
                "the bake no longer writes an S here — this test lost its premise")

        #expect(commandLines(written(baked), "S").isEmpty)
    }

    /// The transform path chooses `_S` per segment too (`buildScale`): a uniform
    /// animation is one number where a stretch is two. Beside any `V` — from a
    /// script, a shape, a filter — that choice is the same stray S.
    @Test("a transform's uniform scale beside a V exports without S")
    func transformStrayScaleIsGone() {
        let ramp = KeyframeTrack([
            Keyframe(time: 0, value: 0, easing: .linear),
            Keyframe(time: 1000, value: 1, easing: .linear),
        ])
        let uniform = TransformCommands.buildScale(
            x: ramp, y: ramp, restingX: 1, restingY: 1, duration: 3000,
        )
        #expect(uniform.contains { $0.kind == .scale },
                "the transform no longer writes an S here — this test lost its premise")

        let mixed = sprite([fade(0, 3000), vector(1000, 3000, 0.4, 0.1)] + uniform)
        #expect(commandLines(written([mixed]), "S").isEmpty)
    }
}

@Suite("OSB export normalisation: animations")
struct OsbExportNormalizationAnimationTests {
    @Test("normalising keeps the animation, and still converts S to V and extends P")
    func keepsAnimation() throws {
        let animation = SpriteAnimation(frameCount: 4, frameDelay: 100, loopType: .loopOnce)
        let sprite = StoryboardSprite(
            id: "a", layer: .foreground, origin: .topCentre, filePath: "sb/a.png",
            defaultX: 0, defaultY: 0,
            commands: [
                Command(easing: .linear, startTime: 0, endTime: 1000, payload: .vectorScale(startX: 1, startY: 2, endX: 1, endY: 2)),
                Command(easing: .linear, startTime: 0, endTime: 500, payload: .scale(start: 3, end: 3)),
                Command(easing: .linear, startTime: 200, endTime: 200, payload: .parameter(.flipHorizontal)),
            ],
            animation: animation,
        )
        let result = try #require(OsbExportNormalization.normalize([sprite]).first)
        #expect(result.animation == animation)
        #expect(!result.commands.contains { $0.kind == .scale })
        let hold = try #require(result.commands.first { $0.kind == .parameter })
        #expect(hold.endTime > hold.startTime)

        let untouched = StoryboardSprite(
            id: "b", layer: .foreground, origin: .centre, filePath: "b.png",
            defaultX: 0, defaultY: 0, animation: animation,
        )
        #expect(OsbExportNormalization.normalize([untouched]).first?.animation == animation)
    }
}
