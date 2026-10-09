import Foundation
import Testing

@testable import StoryboardCore

/// Sliders from a real map (see the header of `constellations-sliders.osu`).
/// osu! cannot be run here, so every assertion is an invariant a wrong
/// implementation would break, with expected values taken from the geometry
/// of the control points rather than from the implementation.
@Suite("Slider path on a real map")
struct SliderFixtureTests {
    private struct Placed {
        let object: HitObject
        let slider: HitObject.Slider
        let path: SliderPath
        let controls: [PlayfieldPoint]
    }

    private static let gameplay: BeatmapGameplay = {
        guard
            let url = Bundle.module.url(
                forResource: "constellations-sliders", withExtension: "osu", subdirectory: "Fixtures",
            ) ?? Bundle.module.url(forResource: "constellations-sliders", withExtension: "osu"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return OsuGameplayParser.parse("") }
        return OsuGameplayParser.parse(text)
    }()

    private func slider(at time: Double) throws -> Placed {
        let object = try #require(Self.gameplay.hitObjects.first { $0.time == time })
        guard case let .slider(slider) = object.kind else {
            Issue.record("object at \(time) is not a slider")
            throw CancellationError()
        }
        let path = SliderPath(slider: slider, head: object.position)
        return Placed(object: object, slider: slider, path: path, controls: [object.position] + slider.points)
    }

    private func d(_ a: PlayfieldPoint, _ b: PlayfieldPoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    private func circumcentre(_ a: PlayfieldPoint, _ b: PlayfieldPoint, _ c: PlayfieldPoint) -> PlayfieldPoint {
        let det = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        let a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y
        return PlayfieldPoint(
            x: (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / det,
            y: (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / det,
        )
    }

    @Test("the fixture parses all nine sliders")
    func fixtureLoaded() {
        #expect(Self.gameplay.hitObjects.count == 9)
        #expect(Self.gameplay.difficulty.sliderMultiplier == 2.4)
    }

    @Test("every slider starts at its head and measures exactly its pixelLength", arguments: [
        2728.0, 4099, 5128, 8728, 9242, 10956, 12327, 32899, 78156,
    ])
    func lengthAndHead(time: Double) throws {
        let placed = try slider(at: time)
        #expect(placed.path.points.first == placed.object.position)
        #expect(abs(placed.path.length - placed.slider.pixelLength) < 1e-6)
        #expect(placed.path.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test("a perfect circle stays on the circumcircle and turns the way its middle point says", arguments: [4099.0, 5128])
    func perfectCircle(time: Double) throws {
        let placed = try slider(at: time)
        let (a, b, c) = (placed.controls[0], placed.controls[1], placed.controls[2])
        let centre = circumcentre(a, b, c)
        let radius = d(a, centre)

        for p in placed.path.points { #expect(abs(d(p, centre) - radius) < 0.05) }

        // Orientation of (a, b, c) must match the turning of the path.
        let expectedSign = ((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)).sign
        var turning = 0.0
        for i in 2..<placed.path.points.count {
            let p0 = placed.path.points[i - 2], p1 = placed.path.points[i - 1], p2 = placed.path.points[i]
            turning += (p1.x - p0.x) * (p2.y - p1.y) - (p1.y - p0.y) * (p2.x - p1.x)
        }
        #expect(turning.sign == expectedSign)

        // The arc a -> c through b is r * theta; pixelLength never exceeds it by much (extension is linear).
        let chord = d(a, c)
        #expect(placed.slider.pixelLength >= chord * 0.9)
    }

    @Test("the first circle passes through its middle control point")
    func circlePassesThroughMiddle() throws {
        let placed = try slider(at: 4099)
        // pixelLength 120 is more than the a->b arc, so b is reached.
        let b = placed.controls[1]
        // Vertices are a couple of units apart, so measure to the segments.
        var best = Double.infinity
        let pts = placed.path.points
        for i in 1..<pts.count {
            let dx = pts[i].x - pts[i - 1].x, dy = pts[i].y - pts[i - 1].y
            let t = max(0, min(1, ((b.x - pts[i - 1].x) * dx + (b.y - pts[i - 1].y) * dy) / (dx * dx + dy * dy)))
            best = min(best, d(b, PlayfieldPoint(x: pts[i - 1].x + t * dx, y: pts[i - 1].y + t * dy)))
        }
        #expect(best < 0.05)
    }

    @Test("a bezier meets its repeated (red) anchors exactly")
    func redAnchors() throws {
        let placed = try slider(at: 2728)
        // B|77:170|77:170|68:90|123:42|123:42|...: the doubled points are anchors.
        for anchor in [PlayfieldPoint(x: 77, y: 170), PlayfieldPoint(x: 123, y: 42)] {
            #expect(placed.path.points.contains(anchor))
        }

        let single = try slider(at: 10956)
        #expect(single.path.points.contains(PlayfieldPoint(x: 414, y: 140)))
        let short = try slider(at: 12327)
        #expect(short.path.points.contains(PlayfieldPoint(x: 500, y: 188)))
    }

    @Test("a linear slider shorter than its control path is truncated on the line")
    func truncatedLinear() throws {
        let placed = try slider(at: 8728)
        let head = placed.object.position, tail = placed.slider.points[0]
        #expect(d(head, tail) > placed.slider.pixelLength)
        #expect(abs(placed.path.length - 60) < 1e-6)
        let end = placed.path.position(at: 1)
        #expect(abs(d(head, end) - 60) < 1e-6)
        // It lies on the head -> tail line.
        let cross = (tail.x - head.x) * (end.y - head.y) - (tail.y - head.y) * (end.x - head.x)
        #expect(abs(cross) < 1e-6)
    }

    @Test("repeats: odd slide counts end on the tail, even ones on the head")
    func repeatEnds() throws {
        let twice = try slider(at: 9242)
        #expect(twice.slider.slides == 2)
        #expect(d(twice.path.position(at: 2, slides: 2), twice.object.position) < 1e-9)
        #expect(d(twice.path.position(at: 1, slides: 2), twice.path.position(at: 1)) < 1e-9)

        let thrice = try slider(at: 78156)
        #expect(thrice.slider.slides == 3)
        #expect(d(thrice.path.position(at: 3, slides: 3), thrice.path.position(at: 1)) < 1e-9)
        #expect(d(thrice.path.position(at: 2, slides: 3), thrice.object.position) < 1e-9)
    }

    @Test("durations follow the governing red and green points")
    func durations() throws {
        let circle = try slider(at: 4099)
        // 120px / (2.4 * 100 * 0.5) = 1 beat of 342.857...ms.
        let end = SliderTiming.endTime(
            of: circle.slider, startTime: 4099, difficulty: Self.gameplay.difficulty,
            controlPoints: Self.gameplay.controlPoints,
        )
        #expect(abs((end - 4099) - 342.857142857143) < 1e-6)

        let repeated = try slider(at: 9242)
        let repeatedEnd = SliderTiming.endTime(
            of: repeated.slider, startTime: 9242, difficulty: Self.gameplay.difficulty,
            controlPoints: Self.gameplay.controlPoints,
        )
        // 60px -> 0.5 beat per span, 2 spans.
        #expect(abs((repeatedEnd - 9242) - 342.857142857143) < 1e-6)
    }
}
