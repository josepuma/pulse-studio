import Foundation
import Testing

@testable import StoryboardCore

/// osu!lazer's kiai star fountains (`KiaiGameplayFountains`, `StarFountain`,
/// `ParticleSpewer`). Expected numbers are derived by hand from the formulas in
/// those files, never by re-running the implementation.
@Suite("Kiai fountains")
struct KiaiFountainsTests {
    // ─── Trigger: one shot per kiai OFF -> ON ────────────────────────────────

    @Test("a kiai that turns on fires one shot at its start time")
    func oneShot() {
        #expect(KiaiFountains.starts(from: [(0, false), (1000, true), (5000, false)]) == [1000])
    }

    @Test("consecutive kiai points do not retrigger")
    func noRetrigger() {
        let starts = KiaiFountains.starts(from: [(0, false), (1000, true), (2000, true), (3000, true), (9000, false)])
        #expect(starts == [1000])
    }

    @Test("kiai that ends and starts again fires again")
    func retrigger() {
        let starts = KiaiFountains.starts(from: [(0, false), (1000, true), (2000, false), (3000, true), (4000, true)])
        #expect(starts == [1000, 3000])
    }

    @Test("a map that opens in kiai fires at its first point; unsorted input is sorted by time")
    func firstPointAndOrder() {
        #expect(KiaiFountains.starts(from: [(500, true)]) == [500])
        #expect(KiaiFountains.starts(from: [(3000, true), (1000, false), (2000, true)]) == [2000])
        #expect(KiaiFountains.starts(from: []).isEmpty)
    }

    @Test("the parser reads kiai from red AND green points")
    func parserReadsBothKinds() {
        let gameplay = OsuGameplayParser.parse("""
        [TimingPoints]
        0,500,4,1,0,100,1,0
        1000,-100,4,1,0,100,0,1
        2000,-100,4,1,0,100,0,1
        3000,500,4,1,0,100,1,0
        4000,500,4,1,0,100,1,1
        """)
        #expect(gameplay.kiaiStarts == [1000, 4000])
    }

    // ─── Shot shape ──────────────────────────────────────────────────────────

    @Test("a shot spews 180/s for 400 ms: 72 particles per side, 1000/180 ms apart")
    func seventyTwoPerSide() {
        for side in FountainSide.allCases {
            let shot = KiaiFountains.shot(startingAt: 10_000, side: side)
            #expect(shot.count == 72)
            #expect(shot.first?.spawn == 0)
            // i * 1000/180: the 72nd (index 71) is at 394.44 ms, still inside the 400 ms.
            #expect(abs((shot.last?.spawn ?? 0) - 71 * 1000.0 / 180.0) < 1e-9)
        }
    }

    @Test("every random draw stays in lazer's ranges")
    func ranges() {
        for side in FountainSide.allCases {
            for particle in KiaiFountains.shot(startingAt: 12_345, side: side) {
                #expect((300.0 ... 1000.0).contains(particle.duration))
                #expect((450.0 ... 600.0).contains(particle.velocityX * side.direction))
                #expect((-1500.0 ... -1300.0).contains(particle.velocityY))
                #expect((-4.0 ... 4.0).contains(particle.startAngle))
                #expect((-2.0 ... 2.0).contains(particle.endAngle))
                #expect((1.8 ... 2.6).contains(particle.endScale))
            }
        }
    }

    // ─── FallingParticle formulas (hand-computed) ────────────────────────────

    private let sample = KiaiFountains.Particle(
        spawn: 0, duration: 500, velocityX: 500, velocityY: -1400,
        startAngle: 3, endAngle: -1, endScale: 2.2,
    )

    @Test("progress, alpha, scale, angle at half the particle's duration")
    func atHalfLife() {
        // t = 250 of 500: progress 0.5.
        #expect(sample.progress(at: 250) == 0.5)
        #expect(sample.alpha(at: 250) == 0.5)
        #expect(abs(sample.scale(at: 250) - 1.6) < 1e-12) // lerp(1, 2.2, .5)
        #expect(abs(sample.angle(at: 250) - 1.0) < 1e-12) // lerp(3, -1, .5)
    }

    @Test("position: start + (velocity + gravity) * t / maxDuration")
    func position() {
        // x = 0 + 500 * 250/1000 = 125
        // y = 50 + (-1400 + 800 * 500/1000 * 0.5) * 250/1000 = 50 + (-1200)(0.25) = -250
        let p = sample.position(at: 250)
        #expect(abs(p.x - 125) < 1e-9)
        #expect(abs(p.y - -250) < 1e-9)
        // At t = 0 it sits on its start position (0, 50): below the screen edge.
        #expect(sample.position(at: 0).x == 0)
        #expect(sample.position(at: 0).y == 50)
    }

    @Test("gravity pulls DOWN (positive y), so the arc turns over")
    func gravityPullsDown() {
        // Same particle with gravity removed would be at y = 50 - 1400 * 0.25 = -300;
        // gravity moves it toward +y, to -250.
        #expect(sample.position(at: 250).y > -300)
        // Late in its life the gravity term dominates the shrinking climb.
        let late = KiaiFountains.Particle(
            spawn: 0, duration: 1000, velocityX: 0, velocityY: -1400,
            startAngle: 0, endAngle: 0, endScale: 2.2,
        )
        // t = 1000: y = 50 + (-1400 + 800) * 1 = -550.
        #expect(abs(late.position(at: 1000).y - -550) < 1e-9)
    }

    @Test("alpha is 1 at birth and 0 at the end of the duration; the particle is then gone")
    func fades() {
        #expect(sample.alpha(at: 0) == 1)
        #expect(sample.alpha(at: 500) == 0)
        #expect(sample.alpha(at: 900) == 0)
        #expect(sample.scale(at: 900) == 2.2)
    }

    // ─── Mapping to the storyboard canvas ────────────────────────────────────

    @Test("the unit mapping is pinned: 768 units tall onto 480, bottom 480, 75 units in")
    func mappingPinned() {
        #expect(FountainMapping.unitScale == 480.0 / 768.0)
        #expect(FountainMapping.unitScale == 0.625)
        #expect(FountainMapping.bottom == 480)
        #expect(FountainMapping.anchorInset == 75)
        #expect(FountainMapping.edges(widescreen: true) == (left: -107, right: 747))
        #expect(FountainMapping.edges(widescreen: false) == (left: 0, right: 640))
    }

    @Test("particles sit at the anchors at birth: left at edge + 75u, right at edge - 75u, both 50u below the bottom")
    func anchors() {
        let particles = KiaiFountains(starts: [1000]).particles(at: 1000, widescreen: true)
        let left = particles.filter { $0.side == .left }
        let right = particles.filter { $0.side == .right }
        // Only the first particle of each side exists at t = T.
        #expect(left.count == 1 && right.count == 1)
        #expect(abs(left[0].position.x - (-107 + 75 * 0.625)) < 1e-9)
        #expect(abs(right[0].position.x - (747 - 75 * 0.625)) < 1e-9)
        #expect(abs(left[0].position.y - (480 + 50 * 0.625)) < 1e-9)
    }

    @Test("the left fountain moves right, the right one moves left")
    func directions() {
        let fountains = KiaiFountains(starts: [1000])
        let birth = fountains.particles(at: 1000, widescreen: true)
        let later = fountains.particles(at: 1100, widescreen: true)
        let leftBirth = birth.first { $0.side == .left }!.position.x
        let rightBirth = birth.first { $0.side == .right }!.position.x
        // The first particle (spawn 0) is the same particle 100 ms on.
        let leftLater = later.filter { $0.side == .left }.map(\.position.x)
        let rightLater = later.filter { $0.side == .right }.map(\.position.x)
        #expect(leftLater.allSatisfy { $0 > FountainMapping.edges(widescreen: true).left })
        #expect(rightLater.allSatisfy { $0 < FountainMapping.edges(widescreen: true).right })
        #expect(leftLater.contains { $0 > leftBirth })
        #expect(rightLater.contains { $0 < rightBirth })
        // And none of the left ones crossed over to the right half.
        #expect(leftLater.allSatisfy { $0 > leftBirth - 1e-9 })
        #expect(rightLater.allSatisfy { $0 < rightBirth + 1e-9 })
    }

    @Test("a particle fades out: alpha in the frame equals 1 - progress")
    func frameAlpha() {
        let fountains = KiaiFountains(starts: [0])
        let shot = KiaiFountains.shot(startingAt: 0, side: .left)
        let spewed = shot[10]
        let time = spewed.spawn + spewed.duration / 4
        let match = fountains.particles(at: time, widescreen: true).filter { $0.side == .left }
            .first { abs($0.alpha - 0.75) < 1e-9 }
        #expect(match != nil)
        #expect(abs((match?.scale ?? 0) - (1 + 0.25 * (spewed.endScale - 1))) < 1e-9)
    }

    // ─── Time window and determinism ─────────────────────────────────────────

    @Test("nothing before the shot nor after T + 1400")
    func window() {
        let fountains = KiaiFountains(starts: [5000])
        #expect(fountains.particles(at: 4999, widescreen: true).isEmpty)
        #expect(!fountains.particles(at: 5000, widescreen: true).isEmpty)
        #expect(!fountains.particles(at: 5000 + 1300, widescreen: true).isEmpty)
        #expect(fountains.particles(at: 5000 + 1400, widescreen: true).isEmpty)
        #expect(fountains.particles(at: 9000, widescreen: true).isEmpty)
        #expect(fountains.particles(at: .nan, widescreen: true).isEmpty)
    }

    @Test("a query is bounded to 144 particles per shot")
    func bounded() {
        let fountains = KiaiFountains(starts: [0])
        for time in stride(from: 0.0, through: 1400, by: 25) {
            #expect(fountains.particles(at: time, widescreen: true).count <= 144)
        }
        // Many hostile starts at once cannot blow the per-frame cost.
        let flood = KiaiFountains(starts: (0 ..< 1000).map { Double($0) })
        #expect(flood.particles(at: 900, widescreen: true).count <= KiaiFountains.maxConcurrentShots * 144)
    }

    @Test("the same time gives the same particles, in any order of asking (scrubbing)")
    func deterministic() {
        let fountains = KiaiFountains(starts: [1000, 6000])
        let first = fountains.particles(at: 1700, widescreen: true)
        _ = fountains.particles(at: 6300, widescreen: true)
        #expect(fountains.particles(at: 1700, widescreen: true) == first)
        #expect(KiaiFountains(starts: [1000, 6000]).particles(at: 1700, widescreen: true) == first)
    }

    @Test("different shots and different sides draw different particles")
    func seedsDiffer() {
        let a = KiaiFountains.shot(startingAt: 1000, side: .left)
        let b = KiaiFountains.shot(startingAt: 2000, side: .left)
        let c = KiaiFountains.shot(startingAt: 1000, side: .right)
        #expect(a.map(\.duration) != b.map(\.duration))
        #expect(a.map(\.duration) != c.map(\.duration))
    }
}
