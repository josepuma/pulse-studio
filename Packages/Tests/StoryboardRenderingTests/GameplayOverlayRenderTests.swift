import CoreGraphics
import Metal
import MetalKit
import StoryboardCore
import Testing

@testable import StoryboardRendering

/// Needs a live GPU, so it is skipped on CI by TYPE name (see
/// `.github/workflows/tests.yml`) and runs locally. Everything that can be
/// decided without a device is in `OverlayPlanTests` / `OverlayBoundaryTests`.
@Suite("Gameplay overlay on the GPU", .serialized)
@MainActor
struct GameplayOverlayRenderTests {
    private static let width = 854
    private static let height = 480

    private func makeMap(_ hitObjects: String) -> GameplayMap {
        let text = """
        [Difficulty]
        CircleSize:4
        ApproachRate:9
        SliderMultiplier:1.4

        [TimingPoints]
        0,500,4,1,0,100,1,0

        [HitObjects]
        \(hitObjects)
        """
        return GameplayMap(OsuGameplayParser.parse(text))
    }

    private func texture(_ device: MTLDevice, width: Int = GameplayOverlayRenderTests.width, height: Int = GameplayOverlayRenderTests.height) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false,
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        return try #require(device.makeTexture(descriptor: descriptor))
    }

    /// Draws one overlay frame into a cleared texture and returns its BGRA bytes.
    private func drawOverlay(
        _ renderer: GameplayOverlayRenderer, map: GameplayMap, time: Double,
        device: MTLDevice, size: (Int, Int) = (width, height),
    ) throws -> [UInt8] {
        let target = try texture(device, width: size.0, height: size.1)
        let queue = try #require(device.makeCommandQueue())
        let commandBuffer = try #require(queue.makeCommandBuffer())

        let clear = MTLRenderPassDescriptor()
        clear.colorAttachments[0].texture = target
        clear.colorAttachments[0].loadAction = .clear
        clear.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        clear.colorAttachments[0].storeAction = .store
        try #require(commandBuffer.makeRenderCommandEncoder(descriptor: clear)).endEncoding()

        renderer.encode(
            into: commandBuffer,
            frame: GameplayFrame.build(map, at: time),
            map: map, time: time, target: target,
            projection: MetalStoryboardRenderer.projectionMatrix(widescreen: true, visible: nil),
            widescreen: true, frameSlot: 0,
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: size.0 * size.1 * 4)
        target.getBytes(&bytes, bytesPerRow: size.0 * 4, from: MTLRegionMake2D(0, 0, size.0, size.1), mipmapLevel: 0)
        return bytes
    }

    private func alpha(_ bytes: [UInt8], x: Int, y: Int, width: Int = GameplayOverlayRenderTests.width) -> Float {
        Float(bytes[(y * width + x) * 4 + 3]) / 255
    }

    @Test("a circle lands at its projected pixel and nothing else is drawn")
    func circleLandsWhereProjected() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try GameplayOverlayRenderer(device: device, drawablePixelFormat: .bgra8Unorm)
        let map = makeMap("256,192,1000,1,0")
        let bytes = try drawOverlay(renderer, map: map, time: 1000, device: device)

        // Playfield (256,192) -> storyboard (320, 248) -> canvas (427, 248).
        let centre = PlayfieldMapping.canvas(PlayfieldPoint(x: 256, y: 192))
        let hit = alpha(bytes, x: Int(centre.x), y: Int(centre.y))
        #expect(abs(hit - Float(GameplayOverlayStyle.bodyOpacity)) < 0.02, "hit=\(hit)")
        #expect(alpha(bytes, x: 5, y: 5) == 0)
        #expect(alpha(bytes, x: Int(centre.x) + 200, y: Int(centre.y)) == 0)
        #expect(renderer.passCount == 1)
    }

    @Test("a slider's border is more opaque and a different colour than its body")
    func sliderBorderReads() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try GameplayOverlayRenderer(device: device, drawablePixelFormat: .bgra8Unorm)
        // A long horizontal slider; sample across it at its middle.
        let map = makeMap("100,192,1000,2,0,L|400:192,1,300")
        let bytes = try drawOverlay(renderer, map: map, time: 1000, device: device)

        let middle = PlayfieldMapping.canvas(PlayfieldPoint(x: 250, y: 192))
        let visual = try #require(GameplayFrame.build(map, at: 1000).first)
        let x = Int(middle.x)
        let centreY = Int(middle.y)
        // Inside the border (the outer 12.8% of the radius), clear of the rim.
        let edgeOffset = Int((visual.radius * 0.94).rounded())
        let body = alpha(bytes, x: x, y: centreY)
        let border = alpha(bytes, x: x, y: centreY - edgeOffset)
        #expect(body > 0.3)
        #expect(border > body + 0.15, "the border must read more opaque than the body (\(border) vs \(body))")

        func rgb(_ y: Int) -> [UInt8] {
            let i = (y * Self.width + x) * 4
            return [bytes[i], bytes[i + 1], bytes[i + 2]]
        }
        #expect(rgb(centreY) != rgb(centreY - edgeOffset))
    }

    @Test("a circle's ring is opaque and white around a translucent coloured body")
    func circleRingReads() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try GameplayOverlayRenderer(device: device, drawablePixelFormat: .bgra8Unorm)
        let map = makeMap("256,192,1000,1,0")
        let bytes = try drawOverlay(renderer, map: map, time: 1000, device: device)
        let centre = PlayfieldMapping.canvas(PlayfieldPoint(x: 256, y: 192))
        let visual = try #require(GameplayFrame.build(map, at: 1000).first)
        let x = Int(centre.x)
        let y = Int(centre.y)
        let ringY = y - Int((visual.radius * 0.93).rounded())
        #expect(alpha(bytes, x: x, y: ringY) > alpha(bytes, x: x, y: y) + 0.15)
        let i = (y * Self.width + x) * 4
        let r = (ringY * Self.width + x) * 4
        // BGRA: the ring is whiter (more red) than the blue-ish body.
        #expect(bytes[r + 2] > bytes[i + 2])
    }

    @Test("an empty frame draws nothing and encodes no pass (S2.3e)")
    func emptyFrame() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try GameplayOverlayRenderer(device: device, drawablePixelFormat: .bgra8Unorm)
        let map = makeMap("256,192,100000,1,0")
        let bytes = try drawOverlay(renderer, map: map, time: 0, device: device)
        #expect(bytes.allSatisfy { $0 == 0 })
        #expect(renderer.passCount == 0)
        #expect(renderer.targetBuildCount == 0)
    }

    @Test("a slider that crosses itself is blended once, not twice, at the crossing")
    func selfOverlapBlendsOnce() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try GameplayOverlayRenderer(device: device, drawablePixelFormat: .bgra8Unorm)
        // An X: (200,100) -> (400,300) -> (400,100) -> (200,300), crossing at (300,200).
        let map = makeMap("200,100,1000,2,0,L|400:300|400:100|200:300,1,764")
        let bytes = try drawOverlay(renderer, map: map, time: 1000, device: device)

        let crossing = PlayfieldMapping.canvas(PlayfieldPoint(x: 300, y: 200))
        let single = PlayfieldMapping.canvas(PlayfieldPoint(x: 400, y: 200))
        let atCrossing = alpha(bytes, x: Int(crossing.x), y: Int(crossing.y))
        let onBody = alpha(bytes, x: Int(single.x), y: Int(single.y))
        #expect(onBody > 0.5, "the body is not where the mesh should be")
        #expect(abs(atCrossing - onBody) < 0.03, "the crossing was blended twice")
    }

    @Test("the offscreen targets follow the drawable size and are built once per size")
    func targetsFollowDrawable() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try GameplayOverlayRenderer(device: device, drawablePixelFormat: .bgra8Unorm)
        let map = makeMap("256,192,1000,1,0")
        _ = try drawOverlay(renderer, map: map, time: 1000, device: device)
        _ = try drawOverlay(renderer, map: map, time: 1000, device: device)
        #expect(renderer.targetBuildCount == 1)
        _ = try drawOverlay(renderer, map: map, time: 1000, device: device, size: (1708, 960))
        #expect(renderer.targetBuildCount == 2)
        renderer.releaseTargets()
        _ = try drawOverlay(renderer, map: map, time: 1000, device: device)
        #expect(renderer.targetBuildCount == 3)
    }

    @Test("the offscreen colour is gamma space, never _srgb")
    func gammaSpace() {
        #expect(GameplayOverlayRenderer.colorFormat == .bgra8Unorm)
        #expect(GameplayOverlayRenderer.colorFormat != .bgra8Unorm_srgb)
    }

    @Test("render(into:) is byte-identical with the overlay set or not (S2.1a)")
    func renderIntoIgnoresOverlay() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalStoryboardRenderer(device: device, pixelFormat: TextureAtlas.pixelFormat)
        let sprite = StoryboardSprite(
            id: "bar", layer: .foreground, origin: .centre, filePath: "missing.png",
            defaultX: 320, defaultY: 240,
            commands: [Command(
                easing: .linear, startTime: 0, endTime: 5000, payload: .fade(start: 1, end: 1),
            )],
        )
        try renderer.setSprites(StoryboardResolver.prepare([sprite])) { _ in nil }

        func frame() throws -> [UInt8] {
            let target = try texture(device)
            #expect(renderer.render(at: 1000, into: target))
            var bytes = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
            target.getBytes(&bytes, bytesPerRow: Self.width * 4, from: MTLRegionMake2D(0, 0, Self.width, Self.height), mipmapLevel: 0)
            return bytes
        }

        let without = try frame()
        renderer.gameplay = makeMap("256,192,1000,1,0")
        let with = try frame()
        #expect(without == with)
        #expect(without.contains { $0 != 0 }, "the storyboard drew nothing, so the comparison proves nothing")
        #expect(renderer.overlayBuildCount == 0, "render(into:) built overlay resources")
    }

    @Test("off it builds nothing; on it builds once; off again it stops drawing (S2.2a-c)")
    func lifecycle() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalStoryboardRenderer(device: device, pixelFormat: TextureAtlas.pixelFormat)
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height), device: device)
        view.colorPixelFormat = TextureAtlas.pixelFormat
        view.drawableSize = CGSize(width: Self.width, height: Self.height)
        // Whether a window-less view hands out drawables is the one thing this
        // test needs from AppKit; say so rather than pass vacuously.
        try #require(view.currentDrawable != nil, "this machine's MTKView gives no drawable without a window")

        for _ in 0 ..< 5 { renderer.draw(at: 1000, in: view) }
        #expect(renderer.overlayBuildCount == 0, "built while off")
        #expect(renderer.overlayPassCount == 0)

        renderer.gameplay = makeMap("256,192,1000,1,0")
        for _ in 0 ..< 5 { renderer.draw(at: 1000, in: view) }
        #expect(renderer.overlayBuildCount == 1, "must build once, not per frame")
        #expect(renderer.overlayPassCount == 5)

        renderer.gameplay = nil
        for _ in 0 ..< 5 { renderer.draw(at: 1000, in: view) }
        #expect(renderer.overlayPassCount == 5, "still drawing after it was turned off")
        #expect(renderer.overlayBuildCount == 1)
    }
}
