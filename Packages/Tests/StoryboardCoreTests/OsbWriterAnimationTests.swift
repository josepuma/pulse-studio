import Testing

@testable import StoryboardCore

/// `Animation` lines have to leave the editor as `Animation` lines: written as
/// a plain `Sprite`, the frames would silently collapse to one picture.
@Suite("OSB writer: animations")
struct OsbWriterAnimationTests {
    private func animated(
        _ animation: SpriteAnimation?,
        commands: [Command] = [],
        loops: [LoopGroup] = [],
    ) -> StoryboardSprite {
        StoryboardSprite(
            id: "a", layer: .foreground, origin: .topCentre, filePath: "sb/a.png",
            defaultX: 320, defaultY: 240, commands: commands, loops: loops,
            animation: animation,
        )
    }

    private func fade(_ start: Double, _ end: Double) -> Command {
        Command(easing: .linear, startTime: start, endTime: end, payload: .fade(start: 0, end: 1))
    }

    @Test("an animated sprite writes the Animation header")
    func header() {
        let text = OsbWriter.write([animated(.init(frameCount: 4, frameDelay: 100, loopType: .loopOnce))])
        #expect(text.contains("Animation,Foreground,TopCentre,\"sb/a.png\",320,240,4,100,LoopOnce\n"))
        #expect(!text.contains("Sprite,"))
    }

    @Test("the frame delay goes through the writer's number formatting")
    func delayFormatting() {
        let text = OsbWriter.write([animated(.init(frameCount: 2, frameDelay: 41.6667, loopType: .loopForever))])
        #expect(text.contains(",2,41.667,LoopForever\n"))
        #expect(!text.contains("100.0"))
    }

    @Test("a plain sprite is written byte for byte as before")
    func plainUnchanged() {
        let text = OsbWriter.write([animated(nil, commands: [fade(0, 1000)])])
        let expected = """
            [Events]
            //Background and Video events
            //Storyboard Layer 0 (Background)
            //Storyboard Layer 1 (Fail)
            //Storyboard Layer 2 (Pass)
            //Storyboard Layer 3 (Foreground)
            Sprite,Foreground,TopCentre,"sb/a.png",320,240
             F,0,0,1000,0,1
            //Storyboard Layer 4 (Overlay)
            //Storyboard Sound Samples

            """
        #expect(text == expected)
    }

    @Test("parse, write, parse keeps the animation with its commands and loops")
    func roundTrip() throws {
        let loop = LoopGroup(startTime: 300, loopCount: 3, commands: [fade(0, 200)])
        let source = animated(
            .init(frameCount: 8, frameDelay: 33.5, loopType: .loopOnce),
            commands: [fade(100, 600)], loops: [loop],
        )
        let first = try #require(OsbParser.parse(OsbWriter.write([source])).sprites.first)
        let second = try #require(OsbParser.parse(OsbWriter.write([first])).sprites.first)

        #expect(first.animation == source.animation)
        #expect(second.animation == first.animation)
        // Command is not Equatable: the written text is the faithful witness.
        #expect(OsbWriter.write([second]) == OsbWriter.write([first]))
        #expect(OsbWriter.write([first]).contains(" L,300,3\n  F,0,0,200,0,1\n"))
        #expect(first.loops.count == 1)
    }

    @Test("an unknown loop type is written canonically as LoopForever")
    func canonicalLoop() throws {
        let input = "[Events]\n//Storyboard Layer 3 (Foreground)\nAnimation,Foreground,Centre,\"a.png\",0,0,3,50,Bogus\n"
        let sprite = try #require(OsbParser.parse(input).sprites.first)
        let text = OsbWriter.write([sprite])
        #expect(text.contains(",3,50,LoopForever\n"))
        #expect(!text.contains("Bogus"))
    }
}
