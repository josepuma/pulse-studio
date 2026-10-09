import Testing

@testable import StoryboardCore

@Suite("Gameplay frame")
struct GameplayFrameTests {
    private func map(ar: Double = 9, _ objects: [HitObject]) -> GameplayMap {
        GameplayMap(GameplayFixture.gameplay(ar: ar, objects: objects))
    }

    @Test("at start - preempt: invisible and 4x; at the hit: opaque and 1x (S2.3a)")
    func approach() throws {
        let m = map([GameplayFixture.circle(at: 1000)])
        let preempt = BeatmapDifficultyMath.preempt(ar: 9)
        let early = try #require(GameplayFrame.build(m, at: 1000 - preempt).first)
        #expect(early.alpha == 0)
        #expect(early.approachScale == BeatmapDifficultyMath.approachStartScale)
        let hit = try #require(GameplayFrame.build(m, at: 1000).first)
        #expect(hit.alpha == 1)
        #expect(hit.approachScale == 1)
        #expect(hit.approachAlpha == 0, "the approach circle is gone at the hit")
    }

    @Test("the circle fades out over the fade-out after the hit (S2.3a)")
    func fadeOut() throws {
        let m = map([GameplayFixture.circle(at: 1000)])
        let half = try #require(GameplayFrame.build(m, at: 1000 + GameplayMap.fadeOut / 2).first)
        #expect(abs(half.alpha - 0.5) < 1e-9)
        #expect(GameplayFrame.build(m, at: 1000 + GameplayMap.fadeOut + 1).isEmpty)
    }

    @Test("a visual carries the map's colour for its combo")
    func comboColour() throws {
        let palette = [ComboColour(r: 1, g: 2, b: 3), ComboColour(r: 4, g: 5, b: 6)]
        var first = GameplayFixture.circle(at: 1000)
        first.comboIndexWithOffsets = 1
        var second = GameplayFixture.circle(at: 1010)
        second.comboIndexWithOffsets = 2
        let gameplay = BeatmapGameplay(
            difficulty: BeatmapDifficulty(), controlPoints: ControlPoints(red: [GameplayFixture.red], green: []),
            hitObjects: [first, second], comboColours: palette,
        )

        let frame = GameplayFrame.build(GameplayMap(gameplay), at: 1010)
        let byIndex = Dictionary(uniqueKeysWithValues: frame.map { ($0.objectIndex, $0.comboColour) })

        // Index modulo palette size, as osu!lazer's LegacySkin reads it.
        #expect(byIndex[0] == palette[1])
        #expect(byIndex[1] == palette[0])
    }

    @Test("fade-in follows the difficulty rule")
    func fadeIn() throws {
        let m = map(ar: 9, [GameplayFixture.circle(at: 1000)])
        let preempt = BeatmapDifficultyMath.preempt(ar: 9)
        let fade = BeatmapDifficultyMath.fadeIn(preempt: preempt)
        let mid = try #require(GameplayFrame.build(m, at: 1000 - preempt + fade / 2).first)
        #expect(abs(mid.alpha - 0.5) < 1e-9)
    }

    @Test("positions are mapped to storyboard space, not raw playfield (S2.3c)")
    func mapped() throws {
        let m = map([GameplayFixture.circle(at: 1000, x: 256, y: 192)])
        let visual = try #require(GameplayFrame.build(m, at: 1000).first)
        #expect(visual.position == PlayfieldMapping.storyboard(PlayfieldPoint(x: 256, y: 192)))
        #expect(visual.position != PlayfieldPoint(x: 256, y: 192))
        #expect(visual.radius == BeatmapDifficultyMath.radius(cs: 4))
    }

    @Test("the combo number is exposed")
    func combo() throws {
        let m = map([GameplayFixture.circle(at: 1000, combo: 3)])
        #expect(try #require(GameplayFrame.build(m, at: 1000).first).comboNumber == 3)
    }

    @Test("the slider ball rides the path with the slides (S2.3b)")
    func ball() throws {
        // 500ms per slide; two slides: out and back.
        let m = map([GameplayFixture.slider(at: 1000, slides: 2)])
        let head = PlayfieldMapping.storyboard(PlayfieldPoint(x: 100, y: 100))
        let tail = PlayfieldMapping.storyboard(PlayfieldPoint(x: 240, y: 100))
        let before = try #require(GameplayFrame.build(m, at: 900).first)
        #expect(before.ball == nil)
        let mid1 = try #require(GameplayFrame.build(m, at: 1250).first.flatMap(\.ball))
        #expect(abs(mid1.x - (head.x + tail.x) / 2) < 1e-6)
        let atTail = try #require(GameplayFrame.build(m, at: 1500).first.flatMap(\.ball))
        #expect(abs(atTail.x - tail.x) < 1e-6)
        let back = try #require(GameplayFrame.build(m, at: 1750).first.flatMap(\.ball))
        #expect(abs(back.x - (head.x + tail.x) / 2) < 1e-6)
    }

    @Test("reverse arrows sit at the ends still to be reversed and alternate (S2.3b)")
    func arrows() throws {
        let one = map([GameplayFixture.slider(at: 1000, slides: 1)])
        #expect(try #require(GameplayFrame.build(one, at: 1100).first).reverseArrows.isEmpty)

        let head = PlayfieldMapping.storyboard(PlayfieldPoint(x: 100, y: 100))
        let tail = PlayfieldMapping.storyboard(PlayfieldPoint(x: 240, y: 100))
        let three = map([GameplayFixture.slider(at: 1000, slides: 3)])
        // First pass: reversals at the tail and then at the head.
        let first = try #require(GameplayFrame.build(three, at: 1100).first).reverseArrows
        #expect(first.count == 2)
        let atTail = try #require(first.first { abs($0.position.x - tail.x) < 1e-6 })
        // At the tail the arrow points back along the path (towards -x).
        #expect(abs(abs(atTail.angle) - .pi) < 1e-6)
        let atHead = try #require(first.first { abs($0.position.x - head.x) < 1e-6 })
        #expect(abs(atHead.angle) < 1e-6)
        // Second pass: the tail reversal is behind us, only the head is left.
        let second = try #require(GameplayFrame.build(three, at: 1600).first).reverseArrows
        #expect(second.count == 1)
        #expect(abs(second[0].position.x - head.x) < 1e-6)
        // Last pass: nothing left to reverse.
        #expect(try #require(GameplayFrame.build(three, at: 2100).first).reverseArrows.isEmpty)
    }

    @Test("a spinner reports its progress (S2.3b)")
    func spinner() throws {
        let m = map([GameplayFixture.spinner(from: 3000, to: 5000)])
        let mid = try #require(GameplayFrame.build(m, at: 4000).first)
        #expect(mid.kind == .spinner)
        #expect(abs((mid.spinnerProgress ?? -1) - 0.5) < 1e-9)
        let before = try #require(GameplayFrame.build(m, at: 2900).first)
        #expect(before.spinnerProgress == 0)
    }

    @Test("objects come latest first")
    func ordering() {
        let m = map([GameplayFixture.circle(at: 1000), GameplayFixture.circle(at: 1100), GameplayFixture.circle(at: 1200)])
        #expect(GameplayFrame.build(m, at: 1050).map(\.objectIndex) == [2, 1, 0])
    }

    @Test("an empty map draws nothing; NaN and huge times do not trap (S2.3e)")
    func degenerate() {
        #expect(GameplayFrame.build(map([]), at: 100).isEmpty)
        let m = map([GameplayFixture.circle(at: 1000)])
        #expect(GameplayFrame.build(m, at: .nan).isEmpty)
        #expect(GameplayFrame.build(m, at: 1e300).isEmpty)
        #expect(GameplayFrame.build(m, at: -.infinity).isEmpty)
    }
}
