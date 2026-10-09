import Foundation

/// The polyline a slider follows, in playfield units, cut or extended to the
/// `pixelLength` the file declares.
///
/// Built from untrusted input: control points are finite-filtered, the output
/// is capped at ``maxVertices`` and every curve falls back to something that
/// cannot produce NaN.
public struct SliderPath: Sendable, Equatable {
    public static let maxVertices = 16_384
    /// Largest deviation (playfield units) a bezier polyline may have.
    public static let bezierTolerance: Double = 0.1
    /// A tighter bound for arcs: their vertices are exact, and the chord
    /// between two of them is what shortens the path.
    public static let arcTolerance: Double = 0.01
    /// A circle through three points with a bigger radius is a straight line
    /// for every purpose here, and its vertex count would explode.
    public static let maxCircleRadius: Double = 100_000
    static let maxArcVertices = 2_048
    static let catmullDetail = 20
    /// Upper bound on the arithmetic spent subdividing beziers (sum of n^2).
    static let bezierWorkBudget = 5_000_000
    static let maxBezierNodes = 2_048
    static let maxBezierDepth = 20

    public let points: [PlayfieldPoint]
    public let length: Double
    /// Distance from the start to each vertex; `cumulative.last == length`.
    private let cumulative: [Double]

    /// - Parameter points: every control point INCLUDING the head.
    /// - Parameter expectedLength: the file's `pixelLength`; `<= 0` or
    ///   non-finite keeps the computed length.
    public init(curve: CurveType, points: [PlayfieldPoint], expectedLength: Double) {
        let controls = Array(
            points.filter { $0.x.isFinite && $0.y.isFinite }.prefix(OsuGameplayParser.maxControlPoints + 1),
        )
        var path: [PlayfieldPoint]
        switch curve {
        case .linear: path = controls
        case .perfect: path = Self.perfect(controls, expectedLength: expectedLength)
        case .bezier: path = Self.bezier(controls)
        case .catmull: path = Self.catmull(controls)
        }
        path = Self.decimated(Self.deduplicated(path))

        let expected = expectedLength.isFinite && expectedLength > 0
            ? min(expectedLength, OsuGameplayParser.maxPixelLength) : nil
        (self.points, self.cumulative) = Self.fitted(path, to: expected)
        length = cumulative.last ?? 0
    }

    /// The slider's own control points, head first.
    public init(slider: HitObject.Slider, head: PlayfieldPoint) {
        self.init(curve: slider.curve, points: [head] + slider.points, expectedLength: slider.pixelLength)
    }

    /// Position after `progress` passes over the path. Progress runs over
    /// `0...slides`: odd passes walk forwards, even ones back, so `slides == 2`
    /// ends on the head. Clamps; NaN is the start.
    public func position(at progress: Double, slides: Int = 1) -> PlayfieldPoint {
        guard let first = points.first else { return PlayfieldPoint(x: 0, y: 0) }
        let passes = max(1, min(slides, OsuGameplayParser.maxSlides))
        guard progress.isFinite || progress == .infinity, !progress.isNaN, length > 0 else { return first }

        let clamped = min(max(progress, 0), Double(passes))
        let pass = min(Int(clamped.rounded(.down)), passes - 1)
        var fraction = clamped - Double(pass)
        if pass % 2 == 1 { fraction = 1 - fraction }
        return point(atDistance: fraction * length)
    }

    private func point(atDistance distance: Double) -> PlayfieldPoint {
        // Last vertex whose cumulative distance does not exceed the target.
        var low = 0
        var high = cumulative.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if cumulative[mid] <= distance { low = mid } else { high = mid - 1 }
        }
        guard low + 1 < points.count else { return points[low] }
        let span = cumulative[low + 1] - cumulative[low]
        let t = span > 0 ? min(max((distance - cumulative[low]) / span, 0), 1) : 0
        let a = points[low], b = points[low + 1]
        return PlayfieldPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    // MARK: - Cut / extend

    private static func distance(_ a: PlayfieldPoint, _ b: PlayfieldPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func deduplicated(_ path: [PlayfieldPoint]) -> [PlayfieldPoint] {
        var result: [PlayfieldPoint] = []
        result.reserveCapacity(path.count)
        for point in path where result.last != point { result.append(point) }
        return result
    }

    private static func decimated(_ path: [PlayfieldPoint]) -> [PlayfieldPoint] {
        guard path.count > maxVertices else { return path }
        let stride = (path.count + maxVertices - 1) / maxVertices
        var result = path.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
        if let last = path.last, result.last != last { result.append(last) }
        return result
    }

    /// osu!'s rule: longer than `expected` is cut, shorter is extended along
    /// its last segment.
    private static func fitted(
        _ path: [PlayfieldPoint], to expected: Double?,
    ) -> ([PlayfieldPoint], [Double]) {
        var points = path
        var cumulative: [Double] = [0]
        for i in 1..<max(points.count, 1) { cumulative.append(cumulative[i - 1] + distance(points[i - 1], points[i])) }
        guard points.count >= 2, let expected, let total = cumulative.last, total != expected else {
            return (points, points.isEmpty ? [] : cumulative)
        }

        if total > expected {
            // First vertex at or past the target; the cut lands on the segment before it.
            let index = cumulative.firstIndex { $0 >= expected } ?? cumulative.count - 1
            let previous = index - 1
            let span = cumulative[index] - cumulative[previous]
            let t = span > 0 ? (expected - cumulative[previous]) / span : 1
            let a = points[previous], b = points[index]
            let end = PlayfieldPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            points = Array(points[..<index]) + [end]
            cumulative = Array(cumulative[..<index]) + [expected]
        } else {
            let a = points[points.count - 2], b = points[points.count - 1]
            let span = distance(a, b)
            guard span > 0 else { return (points, cumulative) }
            let scale = (span + (expected - total)) / span
            points[points.count - 1] = PlayfieldPoint(x: a.x + (b.x - a.x) * scale, y: a.y + (b.y - a.y) * scale)
            cumulative[cumulative.count - 1] = expected
        }
        return (points, cumulative)
    }

    // MARK: - Perfect circle

    private static func perfect(_ controls: [PlayfieldPoint], expectedLength: Double) -> [PlayfieldPoint] {
        guard controls.count == 3 else { return bezier(controls) }
        let a = controls[0], b = controls[1], c = controls[2]

        let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        let radius = distance(a, b) * distance(b, c) * distance(c, a) / (2 * abs(cross))
        guard abs(cross) > 1e-6, radius.isFinite, radius <= maxCircleRadius else { return bezier(controls) }

        let det = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        let a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y
        let centre = PlayfieldPoint(
            x: (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / det,
            y: (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / det,
        )

        let start = atan2(a.y - centre.y, a.x - centre.x)
        var end = atan2(c.y - centre.y, c.x - centre.x)
        while end < start { end += 2 * .pi }
        var direction = 1.0
        var range = end - start
        // a->c rotated a quarter turn points to the side an anticlockwise arc
        // bulges to; if b is on the other side the arc is the long way round.
        let ortho = PlayfieldPoint(x: c.y - a.y, y: -(c.x - a.x))
        if ortho.x * (b.x - a.x) + ortho.y * (b.y - a.y) < 0 {
            direction = -1
            range = 2 * .pi - range
        }

        let step = 2 * acos(max(-1, min(1, 1 - arcTolerance / radius)))
        let wanted = step > 0 ? (range / step).rounded(.up) : Double(maxArcVertices)
        let count = Int(max(2, min(wanted, Double(maxArcVertices))))
        var arc = (0..<count).map { i in
            let angle = start + direction * range * Double(i) / Double(count - 1)
            return PlayfieldPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
        }
        // The ends are the file's own points: trig round-off must not move them.
        arc[0] = a
        arc[arc.count - 1] = c
        return arc
    }

    // MARK: - Bezier

    /// A repeated point is an anchor (a red node in the editor): the curve
    /// ends there and a new one begins, so the path passes through it.
    private static func bezier(_ controls: [PlayfieldPoint]) -> [PlayfieldPoint] {
        guard controls.count >= 2 else { return controls }
        var segments: [[PlayfieldPoint]] = []
        var current = [controls[0]]
        for i in 1..<controls.count {
            if controls[i] == controls[i - 1] {
                if current.count >= 2 { segments.append(current) }
                current = [controls[i]]
            } else {
                current.append(controls[i])
            }
        }
        if current.count >= 2 { segments.append(current) }
        guard !segments.isEmpty else { return [controls[0]] }

        var work = bezierWorkBudget
        var result: [PlayfieldPoint] = []
        for segment in segments { result += flatten(segment, work: &work) }
        return result
    }

    private static func midpoint(_ a: PlayfieldPoint, _ b: PlayfieldPoint) -> PlayfieldPoint {
        PlayfieldPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// Splits at t = 0.5 with de Casteljau.
    private static func split(_ p: [PlayfieldPoint]) -> ([PlayfieldPoint], [PlayfieldPoint]) {
        var left: [PlayfieldPoint] = [], right: [PlayfieldPoint] = []
        var level = p
        while !level.isEmpty {
            left.append(level[0])
            right.append(level[level.count - 1])
            level = zip(level, level.dropFirst()).map { midpoint($0, $1) }
        }
        return (left, right.reversed())
    }

    /// Largest distance the curve can stray from its chord, bounded through
    /// the second differences of the control polygon: n(n-1)/8 * max|d2|.
    private static func isFlat(_ p: [PlayfieldPoint]) -> Bool {
        guard p.count > 2 else { return true }
        var maxSecond = 0.0
        for i in 1..<(p.count - 1) {
            let dx = p[i - 1].x - 2 * p[i].x + p[i + 1].x
            let dy = p[i - 1].y - 2 * p[i].y + p[i + 1].y
            maxSecond = max(maxSecond, (dx * dx + dy * dy).squareRoot())
        }
        let degree = Double(p.count - 1)
        return degree * (degree - 1) / 8 * maxSecond <= bezierTolerance
    }

    /// Level-by-level (not depth-first) so a spent budget leaves a coarse but
    /// even curve instead of detail on one end only.
    private static func flatten(_ segment: [PlayfieldPoint], work: inout Int) -> [PlayfieldPoint] {
        struct Node { var points: [PlayfieldPoint]; var done: Bool }
        var nodes = [Node(points: segment, done: false)]

        for _ in 0..<maxBezierDepth {
            var next: [Node] = []
            var changed = false
            for node in nodes {
                if node.done || isFlat(node.points) {
                    next.append(Node(points: node.points, done: true))
                    continue
                }
                let cost = node.points.count * node.points.count
                if work < cost || nodes.count + next.count >= maxBezierNodes {
                    next.append(Node(points: node.points, done: true))
                    continue
                }
                work -= cost
                let (l, r) = split(node.points)
                next.append(Node(points: l, done: false))
                next.append(Node(points: r, done: false))
                changed = true
            }
            nodes = next
            if !changed { break }
        }

        var result = [segment[0]]
        for node in nodes { if let last = node.points.last { result.append(last) } }
        return result
    }

    // MARK: - Catmull

    private static func catmull(_ controls: [PlayfieldPoint]) -> [PlayfieldPoint] {
        guard controls.count >= 2 else { return controls }
        func find(_ p1: PlayfieldPoint, _ p2: PlayfieldPoint, _ p3: PlayfieldPoint, _ p4: PlayfieldPoint, _ t: Double) -> PlayfieldPoint {
            let t2 = t * t, t3 = t2 * t
            func axis(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
            }
            return PlayfieldPoint(x: axis(p1.x, p2.x, p3.x, p4.x), y: axis(p1.y, p2.y, p3.y, p4.y))
        }

        var result: [PlayfieldPoint] = []
        let last = controls.count - 1
        for i in 0..<last {
            let v1 = i > 0 ? controls[i - 1] : controls[i]
            let v2 = controls[i]
            let v3 = controls[i + 1]
            let v4 = i + 2 <= last
                ? controls[i + 2]
                : PlayfieldPoint(x: 2 * v3.x - v2.x, y: 2 * v3.y - v2.y)
            for step in 0..<catmullDetail {
                result.append(find(v1, v2, v3, v4, Double(step) / Double(catmullDetail)))
            }
        }
        result.append(controls[last])
        return result
    }
}
