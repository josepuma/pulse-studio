import Testing

@testable import StoryboardCore

@Suite("Gameplay parser hardening")
struct OsuGameplayParserFuzzTests {
    private func parse(_ body: String) -> BeatmapGameplay {
        OsuGameplayParser.parse("[HitObjects]\n\(body)")
    }

    private let good = "100,100,1000,1,0"

    /// Every hostile line sits between two good ones: the neighbours must
    /// survive, and the process must too.
    @Test("hostile lines are skipped individually (S1.4a)", arguments: [
        "nan,100,1000,1,0",
        "100,inf,1000,1,0",
        "100,100,-inf,1,0",
        "100,100,1000,nan,0",
        "100,100,1000,1e308,0",
        "100,100,1000,-1e308,0",
        "100,100,1000,9999999999999999999,0",
        "100,100,1000,2,0,B|10:10|nan:nan,1,100",
        "100,100,1000,2,0,B|10:10,nan,100",
        "100,100,1000,2,0,B|10:10,1,inf",
        "100,100,1000,2,0,B|10:10,1,nan",
        "100,100,1000,2,0,",
        "100,100,1000,2,0,B",
        "100,100,1000,2,0,B|,1,100",
        "100,100,1000,2,0,B|abc:def|ghi,1,100",
        "100,100,1000,12,0,nan",
        "100,100,1000,12,0,inf",
        ",,,,",
        "100,100",
        "100,100,1000",
        "abc",
        "",
    ])
    func hostileLine(_ line: String) {
        let parsed = parse("\(good)\n\(line)\n200,200,2000,1,0")

        #expect(parsed.hitObjects.first?.time == 1000)
        #expect(parsed.hitObjects.last?.time == 2000)
        // The hostile line either vanished or was clamped into something
        // finite; it never leaves a NaN behind.
        for object in parsed.hitObjects {
            #expect(object.time.isFinite && object.position.x.isFinite && object.position.y.isFinite)
        }
    }

    @Test("a truncated slider line is skipped and neighbours parse")
    func truncated() {
        let parsed = parse("\(good)\n100,100,1000,2,0,B|10:10,1\n200,200,2000,1,0")

        #expect(parsed.hitObjects.map(\.time) == [1000, 2000])
    }

    @Test("repeats of 2^31 are clamped to maxSlides, negatives to 1")
    func slides() {
        func slides(_ field: String) -> Int? {
            guard case let .slider(slider)? = parse("0,0,0,2,0,L|10:10,\(field),50").hitObjects.first?.kind
            else { return nil }
            return slider.slides
        }

        #expect(slides("2147483648") == OsuGameplayParser.maxSlides)
        #expect(slides("1e308") == OsuGameplayParser.maxSlides)
        #expect(slides("-5") == 1)
        #expect(slides("0") == 1)
        #expect(slides("3") == 3)
    }

    @Test("control points are capped per slider")
    func controlPointCap() {
        let curve = (0..<10_000).map { "\($0):\($0)" }.joined(separator: "|")
        let object = parse("0,0,0,2,0,B|\(curve),1,100").hitObjects.first

        guard case let .slider(slider)? = object?.kind else {
            Issue.record("slider was dropped instead of clamped")
            return
        }
        #expect(slider.points.count == OsuGameplayParser.maxControlPoints)
    }

    @Test("pixel length is clamped into 0...maxPixelLength")
    func pixelLength() {
        func length(_ field: String) -> Double? {
            guard case let .slider(slider)? = parse("0,0,0,2,0,L|10:10,1,\(field)").hitObjects.first?.kind
            else { return nil }
            return slider.pixelLength
        }

        #expect(length("1e308") == OsuGameplayParser.maxPixelLength)
        #expect(length("-5") == 0)
        #expect(length("150") == 150)
    }

    @Test("excess hit objects are dropped, exactly the cap survives (S1.4b)")
    func objectCap() {
        let lines = (0..<(OsuGameplayParser.maxHitObjects + 100))
            .map { "\($0 % 500),0,\($0),1,0" }
            .joined(separator: "\n")

        #expect(parse(lines).hitObjects.count == OsuGameplayParser.maxHitObjects)
    }

    @Test("coordinates and times are clamped")
    func clampsValues() throws {
        let object = try #require(parse("1e308,-1e308,1e308,1,0").hitObjects.first)

        #expect(object.position.x == OsuGameplayParser.coordinateLimit)
        #expect(object.position.y == -OsuGameplayParser.coordinateLimit)
        #expect(object.time == OsuGameplayParser.timeLimit)
    }

    @Test("a spinner end before its start is pulled up to the start")
    func spinnerOrder() throws {
        let object = try #require(parse("0,0,5000,12,0,1000").hitObjects.first)

        #expect(object.kind == .spinner(endTime: 5000))
    }

    @Test("garbage in the other sections never crashes")
    func otherSections() {
        let source = """
        [Difficulty]
        CircleSize
        :::
        [TimingPoints]
        nan,nan,nan
        1e308,-1e308,99999999999999999999,1,0,60,0,0
        ,,,,,,,
        [HitObjects]
        """

        let parsed = OsuGameplayParser.parse(source)
        #expect(parsed.hitObjects.isEmpty)
        #expect(parsed.controlPoints.sv(at: 0).isFinite)
    }
}
