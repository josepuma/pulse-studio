import Foundation
import Testing

@testable import StoryboardCore

private func pt(_ x: Double, _ y: Double) -> PlayfieldPoint { PlayfieldPoint(x: x, y: y) }

private func distance(_ a: PlayfieldPoint, _ b: PlayfieldPoint) -> Double {
    ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
}

/// Distance from `p` to the closest point of the polyline.
private func distance(from p: PlayfieldPoint, to polyline: [PlayfieldPoint]) -> Double {
    var best = Double.infinity
    for i in 1..<polyline.count {
        let a = polyline[i - 1], b = polyline[i]
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared)) : 0
        best = min(best, distance(p, pt(a.x + t * dx, a.y + t * dy)))
    }
    return best
}

private func allFinite(_ path: SliderPath) -> Bool {
    path.length.isFinite && path.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
}

@Suite("Slider path: linear and shared core")
struct SliderPathTests {
    @Test("a straight slider ends where its length says (S1.5a)")
    func linear() {
        let path = SliderPath(curve: .linear, points: [pt(0, 0), pt(100, 0)], expectedLength: 100)

        #expect(abs(path.length - 100) < 1e-9)
        #expect(path.points.first == pt(0, 0))
        let end = path.position(at: 1)
        #expect(abs(end.x - 100) < 1e-9 && abs(end.y) < 1e-9)
        let middle = path.position(at: 0.5)
        #expect(abs(middle.x - 50) < 1e-9)
    }

    @Test("a shorter pixelLength truncates, a longer one extends the last segment (S1.5e)")
    func truncateExtend() {
        let cut = SliderPath(curve: .linear, points: [pt(0, 0), pt(100, 0)], expectedLength: 60)
        #expect(abs(cut.length - 60) < 1e-9)
        #expect(abs(cut.position(at: 1).x - 60) < 1e-9)

        let extended = SliderPath(curve: .linear, points: [pt(0, 0), pt(100, 0)], expectedLength: 150)
        #expect(abs(extended.length - 150) < 1e-9)
        let end = extended.position(at: 1)
        #expect(abs(end.x - 150) < 1e-9 && abs(end.y) < 1e-9)

        // Truncation cuts through a bend, not only inside the first segment.
        let bent = SliderPath(curve: .linear, points: [pt(0, 0), pt(100, 0), pt(100, 100)], expectedLength: 150)
        let bentEnd = bent.position(at: 1)
        #expect(abs(bentEnd.x - 100) < 1e-9 && abs(bentEnd.y - 50) < 1e-9)
    }

    @Test("a multi-point linear path is walked by arc length")
    func multiPointLinear() {
        let path = SliderPath(curve: .linear, points: [pt(0, 0), pt(100, 0), pt(100, 100)], expectedLength: 200)
        #expect(abs(path.length - 200) < 1e-9)
        let p = path.position(at: 0.75)
        #expect(abs(p.x - 100) < 1e-9 && abs(p.y - 50) < 1e-9)
    }

    @Test("a single point or zero length is a valid degenerate path (S1.5f)")
    func degenerate() {
        let single = SliderPath(curve: .linear, points: [pt(5, 5)], expectedLength: 10)
        #expect(single.length == 0)
        #expect(single.position(at: 0.5) == pt(5, 5))

        let empty = SliderPath(curve: .bezier, points: [], expectedLength: 10)
        #expect(allFinite(empty))
        _ = empty.position(at: 0.5)

        let zero = SliderPath(curve: .linear, points: [pt(7, 7), pt(7, 7)], expectedLength: 50)
        #expect(allFinite(zero))
        #expect(zero.position(at: 1) == pt(7, 7))
    }

    @Test("non-finite control points never reach the path")
    func nonFinitePoints() {
        let path = SliderPath(curve: .bezier, points: [pt(0, 0), pt(.nan, 5), pt(.infinity, 1), pt(100, 0)], expectedLength: 100)
        #expect(allFinite(path))
        #expect(path.points.count >= 2)
        // Dropped, not zeroed: a linear path keeps only the real corners.
        let linear = SliderPath(curve: .linear, points: [pt(0, 0), pt(.nan, 5), pt(50, 0), pt(.infinity, 1)], expectedLength: 0)
        #expect(linear.points == [pt(0, 0), pt(50, 0)])
        let none = SliderPath(curve: .linear, points: [pt(0, 0), pt(10, 0)], expectedLength: .nan)
        #expect(abs(none.length - 10) < 1e-9)
    }

    @Test("the path is walked back and forth over slides; progress clamps (S1.5g)")
    func slides() {
        let path = SliderPath(curve: .linear, points: [pt(0, 0), pt(100, 0)], expectedLength: 100)

        #expect(abs(path.position(at: 0.5, slides: 2).x - 50) < 1e-9)
        #expect(abs(path.position(at: 1, slides: 2).x - 100) < 1e-9)
        #expect(abs(path.position(at: 1.25, slides: 2).x - 75) < 1e-9)
        #expect(abs(path.position(at: 1.5, slides: 2).x - 50) < 1e-9)
        #expect(abs(path.position(at: 2, slides: 2).x) < 1e-9)
        // Odd slide counts end on the tail, even ones back on the head.
        #expect(abs(path.position(at: 3, slides: 3).x - 100) < 1e-9)
        #expect(abs(path.position(at: 99, slides: 2).x) < 1e-9)
        #expect(abs(path.position(at: -5, slides: 2).x) < 1e-9)
        #expect(path.position(at: .nan, slides: 2) == pt(0, 0))
        #expect(path.position(at: .infinity, slides: 1).x == 100)
    }
}

@Suite("Slider path: perfect circle")
struct SliderPathCircleTests {
    @Test("a quarter circle has the right length and stays on the circle")
    func quarter() {
        let r = 100.0
        let a = pt(r, 0), b = pt(r * 0.5.squareRoot(), r * 0.5.squareRoot()), c = pt(0, r)
        let path = SliderPath(curve: .perfect, points: [a, b, c], expectedLength: r * .pi / 2)

        #expect(abs(path.length - r * .pi / 2) < 1e-6)
        for p in path.points { #expect(abs(distance(p, pt(0, 0)) - r) < 0.02) }
        let end = path.position(at: 1)
        #expect(distance(end, c) < 0.05)
        // Halfway along the arc is the middle control point.
        #expect(distance(path.position(at: 0.5), b) < 0.3)
    }

    @Test("the arc goes through the middle point, not the long way round (S1.5b)")
    func semicircle() {
        let path = SliderPath(curve: .perfect, points: [pt(0, 0), pt(50, 50), pt(100, 0)], expectedLength: 50 * .pi)

        for p in path.points { #expect(abs(distance(p, pt(50, 0)) - 50) < 0.01) }
        #expect(abs(path.length - 50 * .pi) < 1e-6)
        #expect(path.points.map(\.y).max()! > 49.9)
        #expect(path.points.map(\.y).min()! > -0.02)
        #expect(distance(path.position(at: 1), pt(100, 0)) < 0.05)
    }

    @Test("it bends the same way in the mirrored case")
    func mirrored() {
        // Through (50,-50) instead: the arc must live above the chord in y.
        let path = SliderPath(curve: .perfect, points: [pt(0, 0), pt(50, -50), pt(100, 0)], expectedLength: 50 * .pi)
        #expect(path.points.map(\.y).min()! < -49.9)
        #expect(path.points.map(\.y).max()! < 0.02)
    }

    @Test("collinear, huge-radius and wrong-count inputs fall back to the bezier (S1.5c)")
    func fallbacks() {
        let line: [PlayfieldPoint] = [pt(0, 0), pt(50, 0), pt(100, 0)]
        let perfect = SliderPath(curve: .perfect, points: line, expectedLength: 100)
        let bezier = SliderPath(curve: .bezier, points: line, expectedLength: 100)
        #expect(allFinite(perfect))
        #expect(perfect.points == bezier.points)

        let flat: [PlayfieldPoint] = [pt(0, 0), pt(50, 1e-9), pt(100, 0)]
        let huge = SliderPath(curve: .perfect, points: flat, expectedLength: 100)
        #expect(allFinite(huge))
        #expect(huge.points == SliderPath(curve: .bezier, points: flat, expectedLength: 100).points)

        let four: [PlayfieldPoint] = [pt(0, 0), pt(50, 50), pt(100, 0), pt(150, 50)]
        #expect(SliderPath(curve: .perfect, points: four, expectedLength: 0).points
            == SliderPath(curve: .bezier, points: four, expectedLength: 0).points)

        let two: [PlayfieldPoint] = [pt(0, 0), pt(80, 60)]
        #expect(SliderPath(curve: .perfect, points: two, expectedLength: 0).points
            == SliderPath(curve: .bezier, points: two, expectedLength: 0).points)
    }

    @Test("repeated control points do not produce NaN")
    func repeated() {
        let path = SliderPath(curve: .perfect, points: [pt(10, 10), pt(10, 10), pt(10, 10)], expectedLength: 20)
        #expect(allFinite(path))
    }
}

@Suite("Slider path: bezier and catmull")
struct SliderPathBezierTests {
    @Test("a repeated point splits the curve and the path passes through it (S1.5d)")
    func redAnchor() {
        let path = SliderPath(curve: .bezier, points: [pt(0, 0), pt(100, 0), pt(100, 0), pt(100, 100)], expectedLength: 200)

        #expect(path.points.contains(pt(100, 0)))
        #expect(abs(path.length - 200) < 1e-6)
        let end = path.position(at: 1)
        #expect(distance(end, pt(100, 100)) < 1e-6)
        // Without the split the curve would cut the corner far from (100,0).
        #expect(distance(path.position(at: 0.5), pt(100, 0)) < 1e-6)
    }

    @Test("a flat cubic stays within tolerance of the exact curve")
    func adaptive() {
        let p0 = pt(0, 0), p1 = pt(0, 100), p2 = pt(100, 100), p3 = pt(100, 0)
        let path = SliderPath(curve: .bezier, points: [p0, p1, p2, p3], expectedLength: 0)

        for step in 0...200 {
            let t = Double(step) / 200
            let u = 1 - t
            let x = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x
            let y = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
            #expect(distance(from: pt(x, y), to: path.points) < 0.3)
        }
        #expect(path.points.count < 200)
    }

    @Test("a straight bezier collapses to few vertices")
    func straight() {
        let path = SliderPath(curve: .bezier, points: [pt(0, 0), pt(50, 0), pt(100, 0)], expectedLength: 0)
        #expect(path.points.count <= 8)
        #expect(abs(path.length - 100) < 1e-9)
    }

    @Test("a thousand control points stay bounded and finite")
    func bounded() {
        var points: [PlayfieldPoint] = []
        for i in 0..<OsuGameplayParser.maxControlPoints {
            points.append(pt(Double((i * 37) % 512), Double((i * 91) % 384)))
        }
        let path = SliderPath(curve: .bezier, points: points, expectedLength: 5_000)
        #expect(path.points.count <= SliderPath.maxVertices)
        #expect(allFinite(path))

        let wild = SliderPath(curve: .catmull, points: points, expectedLength: 0)
        #expect(wild.points.count <= SliderPath.maxVertices)
        #expect(allFinite(wild))
    }

    @Test("catmull is smooth and passes through its control points")
    func catmull() {
        let controls: [PlayfieldPoint] = [pt(0, 0), pt(100, 0), pt(100, 100), pt(0, 100)]
        let path = SliderPath(curve: .catmull, points: controls, expectedLength: 0)

        for control in controls { #expect(distance(from: control, to: path.points) < 1e-6) }
        for i in 1..<path.points.count { #expect(distance(path.points[i - 1], path.points[i]) < 8) }
        #expect(distance(path.points.first!, controls[0]) < 1e-9)
        #expect(distance(path.points.last!, controls[3]) < 1e-6)
    }
}
