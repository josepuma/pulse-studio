import Foundation

/// The numbers osu! derives from `[Difficulty]`: object size, how early an
/// object appears and how its approach circle shrinks.
public enum BeatmapDifficultyMath {
    public static let defaultCS: Double = 5
    public static let csRange: ClosedRange<Double> = 0...10
    public static let arRange: ClosedRange<Double> = 0...10
    /// The approach circle starts at this multiple of the object's radius.
    public static let approachStartScale: Double = 4
    /// Fade-in length when the object is visible for at least ``fadeInReference``.
    public static let maximumFadeIn: Double = 400
    public static let fadeInReference: Double = 450

    private static func clamped(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Radius of a circle in playfield units (`54.4 - 4.48 * CS`).
    public static func radius(cs: Double) -> Double {
        54.4 - 4.48 * clamped(cs, csRange, fallback: defaultCS)
    }

    /// Milliseconds an object is visible before its hit time.
    public static func preempt(ar: Double) -> Double {
        let ar = clamped(ar, arRange, fallback: 5)
        // Two linear pieces that meet at AR 5: slower below, faster above.
        if ar < 5 { return 1200 + 600 * (5 - ar) / 5 }
        return 1200 - 750 * (ar - 5) / 5
    }

    /// Fade-in length: 400ms, squeezed once the preempt drops under 450.
    public static func fadeIn(preempt: Double) -> Double {
        guard preempt.isFinite, preempt > 0 else { return 0 }
        return maximumFadeIn * min(1, preempt / fadeInReference)
    }

    /// Approach-circle scale `timeBeforeHit` ms before the hit: 4x at the
    /// start of the preempt, 1x on the hit, clamped outside that window.
    public static func approachScale(timeBeforeHit: Double, preempt: Double) -> Double {
        guard timeBeforeHit.isFinite, preempt.isFinite, preempt > 0 else { return 1 }
        let progress = min(max(timeBeforeHit / preempt, 0), 1)
        return 1 + (approachStartScale - 1) * progress
    }
}
