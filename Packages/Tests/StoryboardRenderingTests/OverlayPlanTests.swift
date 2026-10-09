import CoreGraphics
import StoryboardCore
import StoryboardShaderTypes
import Testing
import simd

@testable import StoryboardRendering

/// The GPU-free half of the gameplay overlay: everything the renderer decides
/// BEFORE it touches Metal, so CI (which has no GPU) still covers it.
@Suite("Overlay plan")
struct OverlayPlanTests {
    private func visual(
        _ index: Int, kind: ObjectVisual.Kind = .circle, x: Double = 100, y: Double = 100,
        alpha: Double = 1, approachScale: Double = 1, approachAlpha: Double = 0,
        ball: PlayfieldPoint? = nil, arrows: [ObjectVisual.ReverseArrow] = [], progress: Double? = nil,
        colour: ComboColour = ComboColour.defaults[0],
    ) -> ObjectVisual {
        ObjectVisual(
            objectIndex: index, kind: kind, position: PlayfieldPoint(x: x, y: y), radius: 40,
            alpha: alpha, approachScale: approachScale, approachAlpha: approachAlpha, comboNumber: 1,
            ball: ball, reverseArrows: arrows, spinnerProgress: progress, comboColour: colour,
        )
    }

    @Test("an empty frame plans nothing (S2.3e)")
    func empty() {
        let plan = OverlayPlan.build([])
        #expect(plan.isEmpty)
        #expect(plan.instances.isEmpty)
        #expect(plan.objects.isEmpty)
    }

    @Test("a circle is one instance at its mapped position, carrying the fade alpha only")
    func circle() throws {
        let plan = OverlayPlan.build([visual(0, x: 123, y: 45, alpha: 0.5)])
        let instance = try #require(plan.instances.first)
        #expect(plan.instances.count == 1)
        #expect(instance.kind == OverlayKindCircle.rawValue)
        #expect(instance.position == SIMD2<Float>(123, 45))
        #expect(instance.radius == 40)
        #expect(abs(instance.alpha - 0.5) < 1e-6)
    }

    @Test("slots count from the EARLIEST object, which is the last of the latest-first list")
    func slots() {
        let plan = OverlayPlan.build([visual(2), visual(1), visual(0)])
        #expect(plan.objects.map(\.objectIndex) == [2, 1, 0])
        #expect(plan.objects.map(\.slot) == [2, 1, 0])
        #expect(plan.slotCount == 3)
    }

    @Test("approach circles are drawn after every object and keep latest-first order")
    func approachLast() {
        let plan = OverlayPlan.build([
            visual(1, approachScale: 3, approachAlpha: 1),
            visual(0, approachScale: 2, approachAlpha: 1),
        ])
        let kinds = plan.instances.map(\.kind)
        #expect(kinds == [
            OverlayKindCircle.rawValue, OverlayKindCircle.rawValue,
            OverlayKindApproach.rawValue, OverlayKindApproach.rawValue,
        ])
        #expect(plan.approach == 2 ..< 4)
        #expect(plan.instances[2].radius == 120)
        #expect(plan.instances[3].radius == 80)
    }

    @Test("an object that has been hit has no approach circle")
    func noApproachAfterHit() {
        let plan = OverlayPlan.build([visual(0, approachScale: 1, approachAlpha: 0)])
        #expect(plan.approach.isEmpty)
        #expect(plan.instances.count == 1)
    }

    @Test("a slider is a body plus a head, its ball and its reverse arrows (S2.3b)")
    func slider() throws {
        let arrow = ObjectVisual.ReverseArrow(position: PlayfieldPoint(x: 300, y: 80), angle: 1.5)
        let plan = OverlayPlan.build([
            visual(0, kind: .slider, ball: PlayfieldPoint(x: 150, y: 90), arrows: [arrow]),
        ])
        let object = try #require(plan.objects.first)
        #expect(object.isSlider)
        let kinds = plan.instances[object.instances].map(\.kind)
        #expect(kinds == [
            OverlayKindCircle.rawValue, OverlayKindReverseArrow.rawValue, OverlayKindBall.rawValue,
        ])
        // The ball is painted last so it rides over the arrows.
        let drawnArrow = plan.instances[object.instances.lowerBound + 1]
        #expect(drawnArrow.angle == 1.5)
        #expect(drawnArrow.position == SIMD2<Float>(300, 80))
    }

    @Test("slider uniforms keep the border opaque and the body translucent")
    func borderOpacity() throws {
        let plan = OverlayPlan.build([visual(0, kind: .slider, alpha: 0.8)])
        let object = try #require(plan.objects.first)
        let values = plan.uniforms(for: object, projection: matrix_identity_float4x4)
        let border = values.alpha
        let body = values.alpha * values.bodyOpacity
        #expect(abs(border - 0.8) < 1e-6, "the border must be drawn at the fade alpha")
        #expect(body < border)
        #expect(values.bodyOpacity == Float(GameplayOverlayStyle.bodyOpacity))
        #expect(values.innerColor != values.color, "the body needs a centreline darker than its rim")
        #expect(values.borderWidth == 0.128)
    }

    @Test("objects of different combos get different colours, divided by 255 with no linearising")
    func comboColours() throws {
        let yellow = ComboColour(r: 246, g: 214, b: 122)
        let blue = ComboColour(r: 52, g: 87, b: 194)
        let plan = OverlayPlan.build([
            visual(1, kind: .slider, colour: blue),
            visual(0, colour: yellow),
        ])

        let slider = try #require(plan.objects.first)
        let circle = try #require(plan.objects.last)
        let circleInstance = plan.instances[circle.instances.lowerBound]
        let sliderHead = plan.instances[slider.instances.lowerBound]

        #expect(circleInstance.color == SIMD4<Float>(246.0 / 255, 214.0 / 255, 122.0 / 255, 1))
        #expect(sliderHead.color == SIMD4<Float>(52.0 / 255, 87.0 / 255, 194.0 / 255, 1))
        #expect(circleInstance.color != sliderHead.color)

        // The slider body is drawn with ITS combo's colour, the centreline darker.
        let uniforms = plan.uniforms(for: slider, projection: matrix_identity_float4x4)
        #expect(uniforms.color == sliderHead.color)
        let shade = GameplayOverlayStyle.innerShade
        #expect(uniforms.innerColor == SIMD4<Float>(52.0 / 255 * shade, 87.0 / 255 * shade, 194.0 / 255 * shade, 1))
        // The border stays white.
        #expect(uniforms.border == SIMD4<Float>(1, 1, 1, 1))
    }

    @Test("a spinner carries its progress")
    func spinner() throws {
        let plan = OverlayPlan.build([visual(0, kind: .spinner, progress: 0.25)])
        let instance = try #require(plan.instances.first)
        #expect(instance.kind == OverlayKindSpinner.rawValue)
        #expect(instance.progress == 0.25)
    }

    @Test("non-finite or invisible objects are dropped, not drawn as garbage")
    func hostileValues() {
        let plan = OverlayPlan.build([
            visual(0, x: .nan), visual(1, y: .infinity), visual(2, alpha: .nan), visual(3, alpha: 0),
        ])
        #expect(plan.isEmpty)
    }

    @Test("depth slabs are disjoint, earlier objects are nearer and the far end stays below the clear value")
    func depth() {
        let count = 50
        var previousEnd: Float = -1
        for slot in 0 ..< count {
            let slab = OverlayDepth.slab(slot: slot, count: count)
            #expect(slab.base >= previousEnd)
            previousEnd = slab.base + slab.size
            #expect(previousEnd < 1)
        }
    }

    @Test("the overlay projection puts storyboard x where a sprite at canvas x + margin lands (S2.4a)")
    func projection() {
        let base = MetalStoryboardRenderer.projectionMatrix(widescreen: true, visible: CGRect(x: 100, y: 50, width: 427, height: 240))
        let overlay = OverlayProjection.matrix(base: base, widescreen: true)
        let storyboard = SIMD4<Float>(373, 285, 0, 1)
        let sprite = SIMD4<Float>(373 + OsuCanvas.xOffset, 285, 0, 1)
        let a = overlay * storyboard
        let b = base * sprite
        #expect(abs(a.x - b.x) < 1e-5)
        #expect(abs(a.y - b.y) < 1e-5)
        // A 4:3 storyboard has no margin.
        let narrow = OverlayProjection.matrix(base: base, widescreen: false)
        let c = narrow * storyboard
        let d = base * storyboard
        #expect(abs(c.x - d.x) < 1e-5)
    }

    @Test("offscreen targets are recreated exactly when the drawable size differs")
    func targetSize() {
        #expect(OverlayTargetSize.needsRecreate(current: nil, drawable: (100, 50)))
        #expect(!OverlayTargetSize.needsRecreate(current: (100, 50), drawable: (100, 50)))
        #expect(OverlayTargetSize.needsRecreate(current: (100, 50), drawable: (101, 50)))
        #expect(OverlayTargetSize.needsRecreate(current: (100, 50), drawable: (100, 49)))
    }

    @Test("resources are built once, on first use, and never when unused (S2.2a, S2.2c)")
    func lazyResource() throws {
        var holder = LazyResource<Int>()
        #expect(holder.buildCount == 0)
        for _ in 0 ..< 10 { _ = holder.value }
        #expect(holder.buildCount == 0)
        for _ in 0 ..< 5 { #expect(holder.acquire { 7 } == 7) }
        #expect(holder.buildCount == 1)
    }

    @Test("a failed build is not retried every frame")
    func lazyFailure() {
        struct Boom: Error {}
        var holder = LazyResource<Int>()
        for _ in 0 ..< 5 { #expect(holder.acquire { throw Boom() } == nil) }
        #expect(holder.buildCount == 1)
    }

    // ─── Kiai fountains ──────────────────────────────────────────────────────

    private func star(
        _ side: FountainSide = .left, x: Double = 10, y: Double = 20, alpha: Double = 0.5,
        scale: Double = 2, angle: Double = 1.25,
    ) -> FountainParticle {
        FountainParticle(side: side, position: PlayfieldPoint(x: x, y: y), alpha: alpha, scale: scale, angle: angle)
    }

    @Test("a fountain star is one white star instance: position, angle, fade alpha, size by scale")
    func fountainInstance() throws {
        let plan = OverlayPlan.build([], fountains: [star()])
        let instance = try #require(plan.instances.first)
        #expect(plan.instances.count == 1)
        #expect(instance.kind == OverlayKindStar.rawValue)
        #expect(instance.position == SIMD2<Float>(10, 20))
        #expect(abs(instance.alpha - 0.5) < 1e-6)
        #expect(abs(instance.angle - 1.25) < 1e-6)
        // 32 units wide at scale 2, 0.625 px per unit: half-width 20.
        #expect(abs(instance.radius - 20) < 1e-5)
        #expect(instance.color == SIMD4<Float>(1, 1, 1, 1))
        #expect(plan.fountain == 0 ..< 1)
    }

    @Test("fountains alone make the plan non-empty, and come AFTER objects and approach circles")
    func fountainsLast() {
        #expect(!OverlayPlan.build([], fountains: [star()]).isEmpty)
        #expect(OverlayPlan.build([], fountains: []).isEmpty)

        let plan = OverlayPlan.build([visual(0, approachScale: 2, approachAlpha: 1)], fountains: [star(), star(.right)])
        #expect(plan.instances.map(\.kind) == [
            OverlayKindCircle.rawValue, OverlayKindApproach.rawValue,
            OverlayKindStar.rawValue, OverlayKindStar.rawValue,
        ])
        #expect(plan.approach == 1 ..< 2)
        #expect(plan.fountain == 2 ..< 4)
    }

    @Test("an invisible or non-finite star is not planned")
    func fountainFilters() {
        let plan = OverlayPlan.build([], fountains: [
            star(alpha: 0), star(x: .nan), star(scale: 0), star(angle: .infinity), star(),
        ])
        #expect(plan.fountain.count == 1)
    }
}
