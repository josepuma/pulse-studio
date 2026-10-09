import Foundation

/// One vertex of a slider body: a position and how far it is from the
/// centreline as a fraction of the radius (0 on the line, 1 on the rim).
public struct SliderMeshVertex: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var d: Float

    public init(x: Float, y: Float, d: Float) {
        self.x = x
        self.y = y
        self.d = d
    }
}

/// A slider body as a triangle LIST (every three vertices are one triangle;
/// winding is not guaranteed, draw without culling).
///
/// A list and not one strip, deliberately: the round joints and caps are fans,
/// which do not stitch into a strip without degenerate triangles, and a list
/// costs the same. The distance attribute is what lets the renderer use it as
/// depth, so a slider that crosses itself resolves without double blending.
public enum SliderMesh {
    public static let defaultMaxVertices = 60_000

    /// Angle covered by one wedge of a fan.
    private static let wedge = Double.pi / 8
    private static let capWedges = 16
    // Worst case per path vertex: two half-quads per segment (12) plus a
    // joint of up to eight wedges (24).
    private static let verticesPerPathPoint = 36
    private static let capVertices = 2 * capWedges * 3

    /// - Parameter translatedBy: added to every vertex, so the caller can hand
    ///   the mesh over already in storyboard space.
    /// - Returns: empty when the radius or cap cannot hold even the end caps.
    public static func build(
        _ path: SliderPath,
        radius: Double,
        maxVertices: Int,
        translatedBy offset: PlayfieldPoint = PlayfieldPoint(x: 0, y: 0),
    ) -> [SliderMeshVertex] {
        guard radius.isFinite, radius > 0, offset.x.isFinite, offset.y.isFinite,
              maxVertices >= capVertices, !path.points.isEmpty
        else { return [] }

        // Keep the worst case under the cap by thinning the polyline.
        let budget = max(2, (maxVertices - capVertices) / verticesPerPathPoint)
        var points = path.points
        if points.count > budget {
            let stride = Double(points.count - 1) / Double(budget - 1)
            points = (0 ..< budget).map { path.points[min(path.points.count - 1, Int((Double($0) * stride).rounded()))] }
        }

        var out: [SliderMeshVertex] = []
        out.reserveCapacity(min(maxVertices, points.count * 24 + capVertices))
        func vertex(_ x: Double, _ y: Double, _ d: Double) -> SliderMeshVertex {
            SliderMeshVertex(x: Float(x + offset.x), y: Float(y + offset.y), d: Float(d))
        }
        func triangle(_ a: SliderMeshVertex, _ b: SliderMeshVertex, _ c: SliderMeshVertex) {
            // Zero-area triangles are wasted work and NaN bait downstream.
            let area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
            guard area.isFinite, area != 0 else { return }
            out.append(contentsOf: [a, b, c])
        }
        /// A fan around `centre` from angle `from` sweeping `delta` radians.
        func fan(_ centre: PlayfieldPoint, from: Double, delta: Double) {
            let steps = max(1, Int((abs(delta) / wedge).rounded(.up)))
            let c = vertex(centre.x, centre.y, 0)
            var previous = vertex(centre.x + radius * cos(from), centre.y + radius * sin(from), 1)
            for i in 1 ... steps {
                let angle = from + delta * Double(i) / Double(steps)
                let next = vertex(centre.x + radius * cos(angle), centre.y + radius * sin(angle), 1)
                triangle(c, previous, next)
                previous = next
            }
        }

        // Unit directions of the non-degenerate segments.
        var directions: [(from: Int, dx: Double, dy: Double)] = []
        for i in 0 ..< points.count - 1 {
            let dx = points[i + 1].x - points[i].x
            let dy = points[i + 1].y - points[i].y
            let length = hypot(dx, dy)
            guard length > 1e-9, length.isFinite else { continue }
            directions.append((i, dx / length, dy / length))
        }

        guard !directions.isEmpty else {
            // Zero length: a disc.
            fan(points[0], from: 0, delta: 2 * .pi)
            return out
        }

        for (i, dir) in directions.enumerated() {
            let a = points[dir.from], b = points[dir.from + 1]
            // Left normal in a y-down space; "left" is only a label.
            let nx = -dir.dy * radius, ny = dir.dx * radius
            let aC = vertex(a.x, a.y, 0), bC = vertex(b.x, b.y, 0)
            let aL = vertex(a.x + nx, a.y + ny, 1), bL = vertex(b.x + nx, b.y + ny, 1)
            let aR = vertex(a.x - nx, a.y - ny, 1), bR = vertex(b.x - nx, b.y - ny, 1)
            triangle(aC, bC, bL); triangle(aC, bL, aL)
            triangle(aC, bC, bR); triangle(aC, bR, aR)

            // Round joint on the outer side of the turn into the next segment.
            if i + 1 < directions.count {
                let next = directions[i + 1]
                let cross = dir.dx * next.dy - dir.dy * next.dx
                let dot = dir.dx * next.dx + dir.dy * next.dy
                let turn = atan2(cross, dot)
                // Outer side: right normal when turning one way, left the other.
                // Rotating the outer normal by the turn angle carries it onto
                // the next segment's, sweeping round the vertex (through the
                // forward direction on a hairpin).
                let startAngle = atan2(turn >= 0 ? -ny : ny, turn >= 0 ? -nx : nx)
                if abs(turn) > 1e-6 { fan(b, from: startAngle, delta: turn) }
            }
        }

        // Round caps. A full disc is overkill for half of it but trivially
        // correct, and the body covers the rest.
        let first = directions[0], last = directions[directions.count - 1]
        let backAngle = atan2(-first.dy, -first.dx)
        fan(points[first.from], from: backAngle - .pi / 2, delta: .pi)
        let forwardAngle = atan2(last.dy, last.dx)
        fan(points[last.from + 1], from: forwardAngle - .pi / 2, delta: .pi)

        return out.count <= maxVertices ? out : []
    }
}
