import Foundation
import StoryboardCore
import StoryboardShaderTypes
import simd

/// What the overlay will draw this frame, decided with no GPU: instance data in
/// draw order plus where each object's instances and depth slab are. The
/// renderer only uploads and encodes it, so all of this is covered on CI.
///
/// Objects arrive latest-first (the order `GameplayFrame` returns) and are
/// painted in that order, so the earliest object lands on top, as in osu!.
struct OverlayPlan {
    struct Object {
        /// Position in `GameplayMap.objects`; picks the slider mesh.
        var objectIndex: Int
        /// 0 is the earliest (nearest) object.
        var slot: Int
        var isSlider: Bool
        /// Fade alpha of the object (its border is drawn at this; bodies scale it).
        var alpha: Float
        /// The slider body at the rim, and at the centreline (the map's combo colour).
        var color: SIMD4<Float>
        var innerColor: SIMD4<Float>
        /// This object's quads: head, ball, arrows.
        var instances: Range<Int>
    }

    var objects: [Object] = []
    var instances: [OverlayQuadInstance] = []
    /// Approach circles, drawn after every object.
    var approach: Range<Int> = 0 ..< 0
    /// Kiai fountain stars, drawn additively after everything else.
    var fountain: Range<Int> = 0 ..< 0
    /// Depth slabs the frame needs (one per frame entry, hidden or not).
    var slotCount = 0

    var isEmpty: Bool { objects.isEmpty && fountain.isEmpty }

    /// The per-draw uniforms of one object (`nil`: the approach circles).
    func uniforms(for object: Object?, projection: matrix_float4x4) -> OverlayDrawUniforms {
        let slab = OverlayDepth.slab(slot: object?.slot ?? 0, count: slotCount)
        return OverlayDrawUniforms(
            projection: projection,
            color: object?.color ?? GameplayOverlayStyle.sliderColor,
            border: GameplayOverlayStyle.borderColor,
            innerColor: object?.innerColor ?? GameplayOverlayStyle.sliderInnerColor,
            slotDepth: slab.base,
            slabSize: slab.size,
            borderWidth: GameplayOverlayStyle.sliderBorderWidth,
            alpha: object?.alpha ?? 1,
            bodyOpacity: Float(GameplayOverlayStyle.bodyOpacity),
        )
    }

    static func build(_ frame: [ObjectVisual], fountains: [FountainParticle] = []) -> OverlayPlan {
        var plan = OverlayPlan()
        plan.slotCount = frame.count
        var approaches: [OverlayQuadInstance] = []

        for (position, visual) in frame.enumerated() {
            // The fade alpha only: the shaders apply the body opacity, so the border stays opaque.
            let alpha = visual.alpha
            guard visual.position.x.isFinite, visual.position.y.isFinite,
                  visual.radius.isFinite, visual.radius > 0, alpha.isFinite, alpha > 0
            else { continue }

            let start = plan.instances.count
            let comboColor = GameplayOverlayStyle.tint(visual.comboColour)
            let centre = SIMD2<Float>(Float(visual.position.x), Float(visual.position.y))
            func quad(
                _ kind: OverlayKind, at point: SIMD2<Float>, radius: Double, alpha: Double,
                color: SIMD4<Float>, angle: Double = 0, progress: Double = 0,
            ) -> OverlayQuadInstance {
                OverlayQuadInstance(
                    position: point, radius: Float(radius), alpha: Float(alpha), color: color,
                    angle: Float(angle), progress: Float(progress), kind: kind.rawValue,
                )
            }

            switch visual.kind {
            case .circle:
                plan.instances.append(quad(OverlayKindCircle, at: centre, radius: visual.radius, alpha: alpha, color: comboColor))
            case .spinner:
                plan.instances.append(quad(
                    OverlayKindSpinner, at: centre, radius: visual.radius, alpha: alpha,
                    color: GameplayOverlayStyle.spinnerColor, progress: visual.spinnerProgress ?? 0,
                ))
            case .slider:
                plan.instances.append(quad(OverlayKindCircle, at: centre, radius: visual.radius, alpha: alpha, color: comboColor))
                for arrow in visual.reverseArrows where arrow.position.x.isFinite && arrow.position.y.isFinite && arrow.angle.isFinite {
                    plan.instances.append(quad(
                        OverlayKindReverseArrow,
                        at: SIMD2<Float>(Float(arrow.position.x), Float(arrow.position.y)),
                        radius: visual.radius * GameplayOverlayStyle.arrowScale, alpha: alpha,
                        color: GameplayOverlayStyle.arrowColor, angle: arrow.angle,
                    ))
                }
                if let ball = visual.ball, ball.x.isFinite, ball.y.isFinite {
                    plan.instances.append(quad(
                        OverlayKindBall, at: SIMD2<Float>(Float(ball.x), Float(ball.y)),
                        radius: visual.radius * GameplayOverlayStyle.ballScale, alpha: alpha,
                        color: GameplayOverlayStyle.ballColor,
                    ))
                }
            }

            plan.objects.append(Object(
                objectIndex: visual.objectIndex,
                // Latest-first list: the last entry is the earliest object.
                slot: frame.count - 1 - position,
                isSlider: visual.kind == .slider,
                alpha: Float(alpha),
                color: comboColor,
                innerColor: GameplayOverlayStyle.innerTint(visual.comboColour),
                instances: start ..< plan.instances.count,
            ))

            if visual.approachAlpha.isFinite, visual.approachAlpha > 0, visual.approachScale.isFinite, visual.approachScale > 0 {
                approaches.append(quad(
                    OverlayKindApproach, at: centre, radius: visual.radius * visual.approachScale,
                    alpha: visual.approachAlpha * GameplayOverlayStyle.approachOpacity,
                    color: GameplayOverlayStyle.approachColor,
                ))
            }
        }

        let approachStart = plan.instances.count
        plan.instances.append(contentsOf: approaches)
        plan.approach = approachStart ..< plan.instances.count

        let fountainStart = plan.instances.count
        for particle in fountains {
            guard particle.position.x.isFinite, particle.position.y.isFinite,
                  particle.alpha.isFinite, particle.alpha > 0,
                  particle.scale.isFinite, particle.scale > 0, particle.angle.isFinite
            else { continue }
            plan.instances.append(OverlayQuadInstance(
                position: SIMD2<Float>(Float(particle.position.x), Float(particle.position.y)),
                radius: Float(FountainMapping.starRadius(scale: particle.scale)),
                alpha: Float(particle.alpha),
                color: GameplayOverlayStyle.fountainColor,
                angle: Float(particle.angle), progress: 0, kind: OverlayKindStar.rawValue,
            ))
        }
        plan.fountain = fountainStart ..< plan.instances.count
        return plan
    }
}

/// Where each object's slider depth slab sits.
///
/// `z = slab.base + distance * slab.size`: inside a slider the centreline is
/// nearest (so a body that crosses itself resolves to one fragment per pixel),
/// and an earlier object's slab is entirely nearer than a later one's, so its
/// prepass is never rejected by the later object's depth.
enum OverlayDepth {
    static func slab(slot: Int, count: Int) -> (base: Float, size: Float) {
        // One slab more than objects: the farthest rim stays strictly below the
        // cleared depth of 1, which `.less` needs to pass.
        let size = 1 / Float(max(count, 1) + 1)
        return (Float(max(slot, 0)) * size, size)
    }
}

/// The overlay's objects are in storyboard space; the margin of the wide canvas
/// is added HERE, once, the same way sprites get it.
enum OverlayProjection {
    static func matrix(base: matrix_float4x4, widescreen: Bool) -> matrix_float4x4 {
        var shift = matrix_identity_float4x4
        shift.columns.3.x = OsuCanvas.offset(widescreen: widescreen)
        return base * shift
    }
}

enum OverlayTargetSize {
    static func needsRecreate(current: (width: Int, height: Int)?, drawable: (width: Int, height: Int)) -> Bool {
        guard let current else { return true }
        return current.width != drawable.width || current.height != drawable.height
    }
}

/// A resource built on first use and never when unused: what keeps the overlay
/// at zero cost while it is off. A failed build is remembered so it is not
/// retried (and recompiled) every frame.
struct LazyResource<Value> {
    private(set) var value: Value?
    private(set) var buildCount = 0
    private var failed = false

    mutating func acquire(_ build: () throws -> Value) -> Value? {
        if let value { return value }
        guard !failed else { return nil }
        buildCount += 1
        do {
            let built = try build()
            value = built
            return built
        } catch {
            failed = true
            return nil
        }
    }
}
