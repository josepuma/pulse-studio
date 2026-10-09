import Foundation

/// An inherited ("green") timing point: a slider-velocity multiplier.
public struct InheritedPoint: Sendable, Equatable {
    public var time: Double
    public var sv: Double

    public init(time: Double, sv: Double) {
        self.time = time
        self.sv = sv
    }
}

/// The red and green timing points of one difficulty, with osu!'s resolution
/// rules for "what is the tempo / slider velocity at time t".
public struct ControlPoints: Sendable, Equatable {
    public static let svRange: ClosedRange<Double> = 0.1...10
    /// osu!'s fallback when a map has no timing points at all (120 BPM).
    public static let defaultBeatLength: Double = 500

    /// Sorted by time.
    public var red: [UninheritedTimingPoint]
    /// Sorted by time, equal times in file order.
    public var green: [InheritedPoint]

    public init(red: [UninheritedTimingPoint] = [], green: [InheritedPoint] = []) {
        self.red = red
        self.green = green
    }

    /// `-100 / beatLength`, clamped. `nil` for a beatLength that is not a
    /// finite negative number: those are not multipliers.
    static func sv(forBeatLength beatLength: Double) -> Double? {
        guard beatLength.isFinite, beatLength < 0 else { return nil }
        let raw = -100 / beatLength
        // A tiny negative beatLength overflows to inf: the clamp absorbs it.
        return min(max(raw, svRange.lowerBound), svRange.upperBound)
    }

    /// Slider velocity at `time`: the latest green point at or after the
    /// governing red point. A red point resets the multiplier to 1.
    public func sv(at time: Double) -> Double {
        let redTime = red.last(where: { $0.time <= time })?.time ?? -.infinity
        guard let green = green.last(where: { $0.time <= time }), green.time >= redTime else { return 1.0 }
        return green.sv
    }

    /// Milliseconds per beat of the governing red point. Before the first one
    /// osu! uses the first; with none, ``defaultBeatLength``.
    public func beatLength(at time: Double) -> Double {
        if let governing = red.last(where: { $0.time <= time }) { return governing.beatLength }
        return red.first?.beatLength ?? Self.defaultBeatLength
    }
}
