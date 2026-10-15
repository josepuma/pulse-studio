import Testing

@testable import StoryboardCore

@Suite("OsbParser")
struct OsbParserTests {
    // ─── Sprite headers ──────────────────────────────────────────────────────

    @Test("parses a sprite header with a quoted path")
    func parsesSpriteHeader() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        """)

        #expect(storyboard.sprites.count == 1)
        let sprite = storyboard.sprites[0]
        #expect(sprite.id == "sprite_0")
        #expect(sprite.layer == .foreground)
        #expect(sprite.origin == .centre)
        #expect(sprite.filePath == "sb/logo.png")
        #expect(sprite.defaultX == 320)
        #expect(sprite.defaultY == 240)
    }

    // A letterbox bar sits at y = 0 (`TopCentre,320,0`). JavaScript's
    // `parseFloat(y) || 240` treated that 0 as missing and hung the bar from
    // the middle of the screen; osu! draws it from the top edge.
    @Test("a position of zero is a position, not a missing field")
    func zeroPositionIsKept() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,TopCentre,"sb/p.png",0,0
        Sprite,Foreground,Centre,"sb/p.png",-0,0.0
        """)

        #expect(storyboard.sprites.map(\.defaultX) == [0, 0])
        #expect(storyboard.sprites.map(\.defaultY) == [0, 0])
    }

    @Test("a missing or unreadable position falls back to the centre")
    func missingPositionFallsBack() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/p.png"
        Sprite,Foreground,Centre,"sb/p.png",abc,
        """)

        #expect(storyboard.sprites.map(\.defaultX) == [320, 320])
        #expect(storyboard.sprites.map(\.defaultY) == [240, 240])
    }

    @Test("keeps commas inside quoted file paths")
    func keepsCommasInsideQuotedPath() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Background,TopLeft,"sb/a,b.png",0,0
        """)

        #expect(storyboard.sprites.first?.filePath == "sb/a,b.png")
    }

    // ─── Animation headers ───────────────────────────────────────────────────

    private func animation(_ line: String) -> SpriteAnimation? {
        OsbParser.parse("[Events]\n\(line)").sprites.first?.animation
    }

    @Test("an Animation header keeps its frame count, delay and loop type")
    func parsesAnimation() throws {
        let storyboard = OsbParser.parse("""
        [Events]
        Animation,Background,Centre,"sb/f.png",320,240,4,100,LoopOnce
        """)

        #expect(storyboard.sprites.count == 1)
        let sprite = try #require(storyboard.sprites.first)
        #expect(sprite.filePath == "sb/f.png")
        #expect(sprite.animation == SpriteAnimation(frameCount: 4, frameDelay: 100, loopType: .loopOnce))
    }

    @Test("a missing or unknown loop type means forever")
    func loopTypeDefaults() {
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,4,100"#)?.loopType == .loopForever)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,4,100,Bogus"#)?.loopType == .loopForever)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,4,100,"#)?.loopType == .loopForever)
    }

    @Test("a header osu! has no defaults for draws a static sprite")
    func invalidHeadersAreStatic() {
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,0,100,LoopOnce"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,-3,100"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,4,0"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,4,-50"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,4,nan"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,4,inf"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,4"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,,100"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,x,100"#) == nil)
    }

    @Test("an Animation with a bad header is still a sprite that draws its file")
    func staticFallbackKeepsSprite() {
        let sprite = OsbParser.parse("[Events]\nAnimation,Background,Centre,\"f.png\",5,6,0,100").sprites.first
        #expect(sprite?.filePath == "f.png")
        #expect(sprite?.defaultX == 5)
    }

    @Test("a frame count over the cap is static, and absurd numbers do not trap")
    func hostileCounts() {
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,5000,100"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,4096,100"#)?.frameCount == 4096)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,4097,100"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,1e30,100"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,99999999999999999999,100"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,nan,100"#) == nil)
        #expect(animation(#"Animation,Background,Centre,"f.png",0,0,4,1e308"#)?.frameDelay == 1e308)
    }

    @Test("commands and loops under an Animation line are still parsed")
    func animationKeepsCommands() throws {
        let storyboard = OsbParser.parse("""
        [Events]
        Animation,Foreground,Centre,"sb/f.png",320,240,3,80,LoopForever
         F,0,1000,2000,0,1
         L,3000,2
          F,0,0,100,1,0
        """)

        let sprite = try #require(storyboard.sprites.first)
        #expect(sprite.animation?.frameCount == 3)
        #expect(sprite.commands.count == 1)
        #expect(sprite.loops.count == 1)
        #expect(sprite.loops.first?.commands.count == 1)
    }

    @Test("a plain Sprite never carries an animation, whatever trails its header")
    func spriteIgnoresAnimationFields() {
        #expect(animation(#"Sprite,Background,Centre,"f.png",0,0,4,100,LoopOnce"#) == nil)
    }

    @Test("unknown layer and origin names fall back to Foreground and Centre")
    func fallsBackOnUnknownEnums() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Nonsense,Bogus,"sb/x.png",10,20
        """)

        #expect(storyboard.sprites.first?.layer == .foreground)
        #expect(storyboard.sprites.first?.origin == .centre)
    }

    @Test("ignores non-sprite event lines")
    func ignoresNonSpriteEvents() {
        let storyboard = OsbParser.parse("""
        [Events]
        //Background and Video events
        0,0,"bg.jpg",0,0
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        """)

        #expect(storyboard.sprites.count == 1)
    }

    // ─── Commands ────────────────────────────────────────────────────────────

    @Test("parses a fade command")
    func parsesFade() throws {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _F,0,1000,2000,0,1
        """)

        let command = try #require(storyboard.sprites.first?.commands.first)
        #expect(command.easing == .linear)
        #expect(command.startTime == 1000)
        #expect(command.endTime == 2000)
        guard case let .fade(start, end) = command.payload else {
            Issue.record("expected a fade payload, got \(command.payload)")
            return
        }
        #expect(start == 0)
        #expect(end == 1)
    }

    @Test("a blank endTime makes the command instant")
    func blankEndTimeMeansInstant() throws {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _F,0,1000,,1
        """)

        let command = try #require(storyboard.sprites.first?.commands.first)
        #expect(command.startTime == 1000)
        #expect(command.endTime == 1000)
    }

    @Test("a blank end value repeats the start value")
    func blankEndValueRepeatsStart() throws {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _S,0,0,500,1.5
        """)

        let command = try #require(storyboard.sprites.first?.commands.first)
        guard case let .scale(start, end) = command.payload else {
            Issue.record("expected a scale payload, got \(command.payload)")
            return
        }
        #expect(start == 1.5)
        #expect(end == 1.5)
    }

    @Test("parses a move command with all four coordinates")
    func parsesMove() throws {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _M,2,0,1000,100,200,300,400
        """)

        let command = try #require(storyboard.sprites.first?.commands.first)
        #expect(command.easing == .in)
        guard case let .move(startX, startY, endX, endY) = command.payload else {
            Issue.record("expected a move payload, got \(command.payload)")
            return
        }
        #expect(startX == 100)
        #expect(startY == 200)
        #expect(endX == 300)
        #expect(endY == 400)
    }

    @Test("parses a colour command")
    func parsesColor() throws {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _C,0,0,1000,255,128,0,0,128,255
        """)

        let command = try #require(storyboard.sprites.first?.commands.first)
        guard case let .color(sr, sg, sb, er, eg, eb) = command.payload else {
            Issue.record("expected a colour payload, got \(command.payload)")
            return
        }
        #expect(sr == 255)
        #expect(sg == 128)
        #expect(sb == 0)
        #expect(er == 0)
        #expect(eg == 128)
        #expect(eb == 255)
    }

    @Test("parses every parameter flag")
    func parsesParameterFlags() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _P,0,0,0,A
        _P,0,0,0,H
        _P,0,0,0,V
        """)

        let payloads = storyboard.sprites.first?.commands.map(\.payload) ?? []
        #expect(payloads.count == 3)

        let kinds: [ParameterKind] = payloads.compactMap {
            guard case let .parameter(kind) = $0 else { return nil }
            return kind
        }
        #expect(kinds == [.additive, .flipHorizontal, .flipVertical])
    }

    @Test("accepts space indentation as well as underscores")
    func acceptsSpaceIndentation() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
         F,0,0,500,0,1
        """)

        #expect(storyboard.sprites.first?.commands.count == 1)
    }

    @Test("skips trigger commands, which are not supported yet")
    func skipsTriggerCommands() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _T,HitSound,0,1000
        _F,0,0,500,0,1
        """)

        // The trigger line is dropped; the fade still lands on the sprite.
        #expect(storyboard.sprites.first?.commands.count == 1)
    }

    // ─── Loops ───────────────────────────────────────────────────────────────

    @Test("parses a loop group with its body")
    func parsesLoop() throws {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _L,1000,4
        __F,0,0,500,0,1
        __F,0,500,1000,1,0
        """)

        let sprite = try #require(storyboard.sprites.first)
        #expect(sprite.loops.count == 1)
        #expect(sprite.loops[0].startTime == 1000)
        #expect(sprite.loops[0].loopCount == 4)
        #expect(sprite.loops[0].commands.count == 2)
        #expect(sprite.commands.isEmpty)
    }

    @Test("a direct command after a loop closes that loop")
    func directCommandClosesLoop() throws {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _L,1000,4
        __F,0,0,500,0,1
        _S,0,0,1000,1,2
        """)

        let sprite = try #require(storyboard.sprites.first)
        #expect(sprite.loops.count == 1)
        #expect(sprite.loops[0].commands.count == 1)
        #expect(sprite.commands.count == 1)
    }

    @Test("a new sprite closes an open loop")
    func newSpriteClosesLoop() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/a.png",320,240
        _L,1000,4
        __F,0,0,500,0,1
        Sprite,Foreground,Centre,"sb/b.png",320,240
        _F,0,0,500,0,1
        """)

        #expect(storyboard.sprites.count == 2)
        #expect(storyboard.sprites[0].loops.count == 1)
        #expect(storyboard.sprites[1].loops.isEmpty)
        #expect(storyboard.sprites[1].commands.count == 1)
    }

    @Test("a loop still open at end of file is committed")
    func loopOpenAtEndOfFileIsCommitted() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _L,1000,4
        __F,0,0,500,0,1
        """)

        #expect(storyboard.sprites.first?.loops.count == 1)
    }

    @Test("an empty loop body is dropped")
    func emptyLoopIsDropped() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _L,1000,4
        Sprite,Foreground,Centre,"sb/b.png",320,240
        """)

        #expect(storyboard.sprites[0].loops.isEmpty)
    }

    @Test("loop count is clamped to at least one")
    func loopCountIsClamped() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        _L,1000,0
        __F,0,0,500,0,1
        """)

        #expect(storyboard.sprites.first?.loops.first?.loopCount == 1)
    }

    // ─── Sections and variables ──────────────────────────────────────────────

    @Test("parses the Variables section")
    func parsesVariables() {
        let storyboard = OsbParser.parse("""
        [Variables]
        $white=255,255,255
        $path=sb/logo.png
        [Events]
        Sprite,Foreground,Centre,"sb/logo.png",320,240
        """)

        #expect(storyboard.variables["$white"] == "255,255,255")
        #expect(storyboard.variables["$path"] == "sb/logo.png")
    }

    @Test("ignores content outside the Events section")
    func ignoresOtherSections() {
        let storyboard = OsbParser.parse("""
        [General]
        Sprite,Foreground,Centre,"sb/ignored.png",320,240
        [Events]
        Sprite,Foreground,Centre,"sb/kept.png",320,240
        """)

        #expect(storyboard.sprites.count == 1)
        #expect(storyboard.sprites.first?.filePath == "sb/kept.png")
    }

    @Test("handles CRLF line endings")
    func handlesCRLF() {
        let storyboard = OsbParser.parse(
            "[Events]\r\nSprite,Foreground,Centre,\"sb/logo.png\",320,240\r\n_F,0,0,500,0,1\r\n",
        )

        #expect(storyboard.sprites.count == 1)
        #expect(storyboard.sprites.first?.commands.count == 1)
    }

    @Test("skips comments and blank lines")
    func skipsCommentsAndBlanks() {
        let storyboard = OsbParser.parse("""
        [Events]
        //a comment

        Sprite,Foreground,Centre,"sb/logo.png",320,240

        _F,0,0,500,0,1
        """)

        #expect(storyboard.sprites.count == 1)
        #expect(storyboard.sprites.first?.commands.count == 1)
    }

    @Test("an empty source yields an empty storyboard")
    func emptySource() {
        let storyboard = OsbParser.parse("")
        #expect(storyboard.sprites.isEmpty)
        #expect(storyboard.variables.isEmpty)
    }

    @Test("commands before any sprite are ignored")
    func commandsWithoutSpriteAreIgnored() {
        let storyboard = OsbParser.parse("""
        [Events]
        _F,0,0,500,0,1
        """)

        #expect(storyboard.sprites.isEmpty)
    }

    @Test("sprite ids increment in file order")
    func spriteIdsIncrement() {
        let storyboard = OsbParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/a.png",320,240
        Sprite,Foreground,Centre,"sb/b.png",320,240
        Sprite,Foreground,Centre,"sb/c.png",320,240
        """)

        #expect(storyboard.sprites.map(\.id) == ["sprite_0", "sprite_1", "sprite_2"])
    }
}
