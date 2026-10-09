import Foundation

/// Which corner a fountain stands in. The sign is lazer's `Shoot(direction)`:
/// `+1` for the left fountain, `-1` for the right one.
public enum FountainSide: Int, Sendable, CaseIterable {
    case left = 0
    case right = 1

    /// Multiplies the horizontal velocity: the left fountain throws to the
    /// right, the right one to the left.
    public var direction: Double { self == .left ? 1 : -1 }
}

/// One star of a fountain, ready to draw: storyboard space, no GPU.
public struct FountainParticle: Sendable, Equatable {
    public var side: FountainSide
    /// Centre, in storyboard coordinates (the overlay projection adds the
    /// wide-canvas margin, like every other overlay position).
    public var position: PlayfieldPoint
    /// `1 - progress`.
    public var alpha: Double
    /// 1 at birth, growing to its `endScale`.
    public var scale: Double
    /// Radians, as lazer's `transformPosition` takes them: positive turns the
    /// star counter-clockwise on screen.
    public var angle: Double

    public init(side: FountainSide, position: PlayfieldPoint, alpha: Double, scale: Double, angle: Double) {
        self.side = side
        self.position = position
        self.alpha = alpha
        self.scale = scale
        self.angle = angle
    }
}

/// How lazer's UI units land on the storyboard canvas. The ONE place that
/// knows.
///
/// - VERIFIED in ppy/osu master: `OsuGame.ScalingContainerTargetDrawSize` is
///   1024x768 and `ScalingContainer` wraps the game in a
///   `DrawSizePreservingFillContainer`, so on a screen at least as wide as 4:3
///   the screen is 768 units tall: 1 unit = 480/768 storyboard px.
/// - UNVERIFIED, needs a capture of a real lazer kiai start: that the
///   fountains' screen corners coincide with the storyboard canvas edges
///   (widescreen -107...747, otherwise 0...640) and its bottom at 480.
public enum FountainMapping {
    public static let unitScale: Double = 480.0 / 768.0
    /// Both fountains are anchored to the bottom edge.
    public static let bottom: Double = 480
    /// `X = 75` / `X = -75` of `KiaiGameplayFountains`, in lazer units.
    public static let anchorInset: Double = 75
    /// UNVERIFIED: the width of lazer's `Menu/fountain-star` texture, which is
    /// osu-resources artwork we do not ship. Only the drawn size depends on it.
    public static let starSize: Double = 32

    public static func edges(widescreen: Bool) -> (left: Double, right: Double) {
        widescreen ? (-107, 747) : (0, 640)
    }

    /// Half the star's drawn width in storyboard px at `scale`.
    public static func starRadius(scale: Double) -> Double {
        starSize / 2 * scale * unitScale
    }
}

/// The star fountains osu!lazer fires at the start of every kiai section,
/// reproduced as a pure function of time.
///
/// Sources (ppy/osu, MIT): `KiaiGameplayFountains.cs` (trigger, two fountains,
/// 400 ms shoot, 180/s), `StarFountain.cs` (particle ranges) and
/// `ParticleSpewer.cs` (`FallingParticle` formulas, gravity). Every constant
/// below is theirs.
///
/// Deliberate deviation: lazer draws its randomness from the non-deterministic
/// `RNG`, so two plays differ. An editor scrubs, so each shot is seeded from its
/// start time and side instead: the same time always gives the same stars.
public struct KiaiFountains: Sendable, Equatable {
    // ─── lazer's constants ───────────────────────────────────────────────────
    public static let shootDuration: Double = 400
    public static let particlesPerSecond: Double = 180
    /// `maxDuration`: the longest a particle lives.
    public static let maxDuration: Double = 1000
    public static let minParticleDuration: Double = 300
    public static let gravity: Double = 800
    public static let startY: Double = 50
    public static let velocityXRange: ClosedRange<Double> = 450 ... 600
    public static let velocityYBase: Double = -1400
    public static let velocityYVariance: Double = 100
    public static let startAngleVariance: Double = 4
    public static let endAngleVariance: Double = 2
    public static let endScaleBase: Double = 2.2
    public static let endScaleVariance: Double = 0.4

    /// 180/s over 400 ms.
    public static let particlesPerShot = 72
    /// From the shot to its last particle's end: 400 ms of spewing plus the
    /// longest life, 1400 ms.
    public static let visibleSpan: Double = shootDuration + maxDuration
    /// Shots drawn at once at most. Real maps are a shot every few seconds; a
    /// hostile one could stack thousands of starts inside 1.4 s.
    public static let maxConcurrentShots = 8

    /// A spewed particle in lazer units, relative to its fountain's anchor
    /// (`y` grows downward). `FallingParticle` of `ParticleSpewer.cs`.
    public struct Particle: Sendable, Equatable {
        /// ms after the shot at which it is born.
        public var spawn: Double
        public var duration: Double
        public var velocityX: Double
        public var velocityY: Double
        public var startAngle: Double
        public var endAngle: Double
        public var endScale: Double

        public init(
            spawn: Double, duration: Double, velocityX: Double, velocityY: Double,
            startAngle: Double, endAngle: Double, endScale: Double,
        ) {
            self.spawn = spawn
            self.duration = duration
            self.velocityX = velocityX
            self.velocityY = velocityY
            self.startAngle = startAngle
            self.endAngle = endAngle
            self.endScale = endScale
        }

        /// `t` is milliseconds since the particle was born.
        public func progress(at t: Double) -> Double { min(max(t / duration, 0), 1) }
        public func alpha(at t: Double) -> Double { 1 - progress(at: t) }
        public func scale(at t: Double) -> Double { 1 + (endScale - 1) * progress(at: t) }
        public func angle(at t: Double) -> Double { startAngle + (endAngle - startAngle) * progress(at: t) }

        /// `StartPosition + (Velocity + (0, gravity * Duration / maxDuration * progress)) * t / maxDuration`
        public func position(at t: Double) -> (x: Double, y: Double) {
            let pull = KiaiFountains.gravity * duration / KiaiFountains.maxDuration * progress(at: t)
            return (
                x: (velocityX) * t / KiaiFountains.maxDuration,
                y: KiaiFountains.startY + (velocityY + pull) * t / KiaiFountains.maxDuration,
            )
        }
    }

    /// Shot start times, ascending: each kiai OFF -> ON.
    public let starts: [Double]

    public init(starts: [Double]) {
        self.starts = starts.filter(\.isFinite).sorted()
    }

    /// `KiaiGameplayFountains.Update` shoots when the effect point is kiai and
    /// the previous one was not: one shot per transition, so consecutive kiai
    /// points never retrigger. `points` are every timing point (red and green),
    /// the way lazer's effect points are; they are ordered by time here, equal
    /// times keeping file order.
    public static func starts(from points: [(time: Double, kiai: Bool)]) -> [Double] {
        let ordered = points.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
        var result: [Double] = []
        var wasKiai = false
        for point in ordered {
            if point.kiai, !wasKiai { result.append(point.time) }
            wasKiai = point.kiai
        }
        return result
    }

    /// Every particle of one fountain's shot (72), in spawn order.
    ///
    /// Draw order per particle follows lazer's `CreateParticle`: duration, the
    /// two angles, the end scale, then the velocity.
    public static func shot(startingAt start: Double, side: FountainSide) -> [Particle] {
        // The start is a whole millisecond (the parser rounds it); the side is
        // mixed in so the two fountains do not mirror each other.
        let seed = UInt64(bitPattern: Int64(start.rounded())) ^ (UInt64(side.rawValue + 1) &* 0xD1B5_4A32_D192_ED03)
        let base = EffectRandom(seed: seed)
        return (0 ..< particlesPerShot).map { index in
            var random = base.stream(index)
            let duration = random.between(minParticleDuration, maxDuration)
            let startAngle = random.symmetric(startAngleVariance)
            let endAngle = random.symmetric(endAngleVariance)
            let endScale = endScaleBase + random.symmetric(endScaleVariance)
            let velocityX = side.direction * random.between(velocityXRange.lowerBound, velocityXRange.upperBound)
            let velocityY = velocityYBase + random.symmetric(velocityYVariance)
            return Particle(
                spawn: Double(index) * 1000 / particlesPerSecond,
                duration: duration, velocityX: velocityX, velocityY: velocityY,
                startAngle: startAngle, endAngle: endAngle, endScale: endScale,
            )
        }
    }

    /// The stars alive at `time`, in storyboard space. Only the shots within
    /// ``visibleSpan`` before `time` are looked at.
    public func particles(at time: Double, widescreen: Bool) -> [FountainParticle] {
        guard time.isFinite, !starts.isEmpty else { return [] }
        // First shot not yet over, via binary search; then up to `time`.
        var low = 0, high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= time - Self.visibleSpan { low = mid + 1 } else { high = mid }
        }
        var end = low
        while end < starts.count, starts[end] <= time { end += 1 }
        let first = max(low, end - Self.maxConcurrentShots)

        let edges = FountainMapping.edges(widescreen: widescreen)
        let unit = FountainMapping.unitScale
        var result: [FountainParticle] = []
        for start in starts[first ..< end] {
            for side in FountainSide.allCases {
                let anchorX = side == .left
                    ? edges.left + FountainMapping.anchorInset * unit
                    : edges.right - FountainMapping.anchorInset * unit
                for particle in Self.shot(startingAt: start, side: side) {
                    let age = time - start - particle.spawn
                    guard age >= 0 else { continue }
                    let alpha = particle.alpha(at: age)
                    guard alpha > 0 else { continue }
                    let local = particle.position(at: age)
                    result.append(FountainParticle(
                        side: side,
                        position: PlayfieldPoint(
                            x: anchorX + local.x * unit,
                            y: FountainMapping.bottom + local.y * unit,
                        ),
                        alpha: alpha,
                        scale: particle.scale(at: age),
                        angle: particle.angle(at: age),
                    ))
                }
            }
        }
        return result
    }
}
