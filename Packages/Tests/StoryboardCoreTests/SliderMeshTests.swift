import Foundation
import Testing

@testable import StoryboardCore

@Suite("Slider mesh")
struct SliderMeshTests {
    private static let radius = 30.0

    private func straight(length: Double = 100) -> SliderPath {
        SliderPath(
            curve: .linear,
            points: [PlayfieldPoint(x: 0, y: 0), PlayfieldPoint(x: length, y: 0)],
            expectedLength: length,
        )
    }

    private func distanceToPolyline(_ x: Double, _ y: Double, _ pts: [PlayfieldPoint]) -> Double {
        var best = Double.infinity
        for i in 0 ..< max(1, pts.count - 1) {
            let a = pts[i], b = pts[min(i + 1, pts.count - 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? min(max(((x - a.x) * dx + (y - a.y) * dy) / len2, 0), 1) : 0
            best = min(best, hypot(x - (a.x + t * dx), y - (a.y + t * dy)))
        }
        return best
    }

    @Test("a straight slider is a triangle list inside the radius, with d in [0,1] (S1.7a)")
    func straightSlider() {
        let path = straight()
        let mesh = SliderMesh.build(path, radius: Self.radius, maxVertices: SliderMesh.defaultMaxVertices)
        #expect(!mesh.isEmpty)
        #expect(mesh.count % 3 == 0)
        for v in mesh {
            #expect(v.x.isFinite && v.y.isFinite && v.d.isFinite)
            #expect(v.d >= 0 && v.d <= 1)
            let dist = distanceToPolyline(Double(v.x), Double(v.y), path.points)
            #expect(dist <= Self.radius + 1e-3)
            // The attribute is distance-to-centreline over the radius.
            #expect(abs(dist / Self.radius - Double(v.d)) < 1e-3)
        }
        #expect(mesh.contains { $0.d == 0 })
        #expect(mesh.contains { $0.d == 1 })
    }

    @Test("the body reaches radius beyond both ends: round caps exist")
    func caps() {
        let mesh = SliderMesh.build(straight(), radius: Self.radius, maxVertices: SliderMesh.defaultMaxVertices)
        #expect(mesh.map { Double($0.x) }.min()! < -Self.radius + 1)
        #expect(mesh.map { Double($0.x) }.max()! > 100 + Self.radius - 1)
    }

    @Test("a pathological slider stays under the vertex cap without NaN (S1.7b)")
    func pathological() {
        var pts: [PlayfieldPoint] = []
        for i in 0 ..< 1_000 { pts.append(PlayfieldPoint(x: Double(i % 2) * 500, y: Double(i) * 0.3)) }
        let path = SliderPath(curve: .linear, points: pts, expectedLength: 0)
        #expect(path.points.count > 900)
        // Small enough that the full polyline cannot fit: it must be thinned.
        let cap = 5_000
        let mesh = SliderMesh.build(path, radius: Self.radius, maxVertices: cap)
        #expect(mesh.count <= cap)
        #expect(mesh.count % 3 == 0)
        #expect(!mesh.isEmpty)
        #expect(mesh.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.d.isFinite })
    }

    @Test("a 180-degree turn gives no NaN and no degenerate triangles (S1.7c)")
    func hairpin() {
        let path = SliderPath(
            curve: .linear,
            points: [PlayfieldPoint(x: 0, y: 0), PlayfieldPoint(x: 100, y: 0), PlayfieldPoint(x: 0, y: 0.001)],
            expectedLength: 0,
        )
        let mesh = SliderMesh.build(path, radius: Self.radius, maxVertices: SliderMesh.defaultMaxVertices)
        #expect(!mesh.isEmpty)
        #expect(mesh.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.d.isFinite })
        for i in stride(from: 0, to: mesh.count, by: 3) {
            let a = mesh[i], b = mesh[i + 1], c = mesh[i + 2]
            let area = abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
            #expect(area > 0, "triangle \(i / 3) is degenerate")
        }
    }

    @Test("a corner is filled with a round joint on its outer side")
    func joint() {
        let path = SliderPath(
            curve: .linear,
            points: [PlayfieldPoint(x: 0, y: 0), PlayfieldPoint(x: 100, y: 0), PlayfieldPoint(x: 100, y: 100)],
            expectedLength: 0,
        )
        let mesh = SliderMesh.build(path, radius: Self.radius, maxVertices: SliderMesh.defaultMaxVertices)
        // The outer corner of an L is rounded: the square corner (130, -30)
        // lies beyond the radius of the vertex (100, 0) and must be empty.
        let outerCorner = mesh.filter { Double($0.x) > 99 && Double($0.y) < 1 && hypot(Double($0.x) - 100, Double($0.y)) > Self.radius + 1e-3 }
        #expect(outerCorner.isEmpty)
        // ...and its rim is there: a vertex on the diagonal of the outer wedge.
        #expect(mesh.contains { $0.d == 1 && Double($0.x) > 100 + 1 && Double($0.y) < -1 && abs(hypot(Double($0.x) - 100, Double($0.y)) - Self.radius) < 1e-3 })
    }

    @Test("a single-point path is a disc")
    func disc() {
        let path = SliderPath(curve: .linear, points: [PlayfieldPoint(x: 10, y: 10)], expectedLength: 0)
        let mesh = SliderMesh.build(path, radius: Self.radius, maxVertices: SliderMesh.defaultMaxVertices)
        #expect(!mesh.isEmpty)
        #expect(mesh.count % 3 == 0)
        #expect(mesh.allSatisfy { hypot(Double($0.x) - 10, Double($0.y) - 10) <= Self.radius + 1e-3 })
    }

    @Test("a bad radius or cap builds nothing")
    func invalid() {
        let path = straight()
        #expect(SliderMesh.build(path, radius: .nan, maxVertices: 1000).isEmpty)
        #expect(SliderMesh.build(path, radius: 0, maxVertices: 1000).isEmpty)
        #expect(SliderMesh.build(path, radius: 10, maxVertices: 3).isEmpty)
    }

    @Test("the offset translates every vertex")
    func offset() {
        let base = SliderMesh.build(straight(), radius: 10, maxVertices: 5000)
        let moved = SliderMesh.build(straight(), radius: 10, maxVertices: 5000, translatedBy: PlayfieldPoint(x: 64, y: 48))
        #expect(base.count == moved.count)
        for (a, b) in zip(base, moved) {
            #expect(abs(b.x - a.x - 64) < 1e-3)
            #expect(abs(b.y - a.y - 48) < 1e-3)
            #expect(a.d == b.d)
        }
    }
}
