import Metal
import StoryboardCore
import StoryboardShaderTypes
import simd

/// Draws the gameplay overlay: hit objects over the storyboard, editor only.
///
/// Two passes per frame, both encoded into the command buffer the storyboard
/// already uses, after the storyboard and before presenting:
///
/// 1. an OFFSCREEN pass (colour `bgra8Unorm` + `depth32Float`, sized to the
///    drawable) where objects are painted latest-first so the earliest lands on
///    top. A slider is drawn twice: a depth-only prepass (`less`, colour mask
///    none) and then the colour pass (`equal`), with depth = distance to the
///    centreline, so a body crossing itself blends once per pixel instead of
///    twice.
/// 2. a COMPOSITE of that target onto the drawable (`load`, premultiplied
///    over), so the storyboard under it is untouched.
///
/// Nothing here exists until the overlay is first switched on, and the offscreen
/// targets are released when it is switched off.
@MainActor
final class GameplayOverlayRenderer {
    /// Colour is gamma-space like the storyboard: never `_srgb`, which would
    /// convert on read and write and change every overlap (see CLAUDE.md).
    static let colorFormat = MTLPixelFormat.bgra8Unorm
    static let depthFormat = MTLPixelFormat.depth32Float

    private let device: MTLDevice
    private let quadPipeline: MTLRenderPipelineState
    private let sliderPrepassPipeline: MTLRenderPipelineState
    private let sliderColorPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let prepassDepth: MTLDepthStencilState
    private let colorDepth: MTLDepthStencilState
    private let noDepth: MTLDepthStencilState

    private var colorTarget: MTLTexture?
    private var depthTarget: MTLTexture?

    private var instanceBuffers: [MTLBuffer?] = [nil, nil, nil]
    private var vertexBuffers: [MTLBuffer?] = [nil, nil, nil]

    /// Frames the overlay has encoded, for tests (zero while it is off).
    private(set) var passCount = 0
    /// Times the offscreen targets were (re)created.
    private(set) var targetBuildCount = 0

    init(device: MTLDevice, drawablePixelFormat: MTLPixelFormat) throws {
        self.device = device
        let library = try Self.makeLibrary(device: device)

        func function(_ name: String) throws -> MTLFunction {
            guard let found = library.makeFunction(name: name) else {
                throw RendererError.missingShaderFunction(name)
            }
            return found
        }

        func pipeline(
            _ label: String, vertex: String, fragment: String?, format: MTLPixelFormat,
            depth: Bool, colorMask: MTLColorWriteMask = .all, blend: Bool = true,
        ) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = label
            descriptor.vertexFunction = try function(vertex)
            if let fragment { descriptor.fragmentFunction = try function(fragment) }
            guard let attachment = descriptor.colorAttachments[0] else {
                throw RendererError.pipelineCreationFailed(label)
            }
            attachment.pixelFormat = format
            attachment.writeMask = colorMask
            attachment.isBlendingEnabled = blend
            // Premultiplied over, like the storyboard's normal blend.
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            if depth { descriptor.depthAttachmentPixelFormat = Self.depthFormat }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        quadPipeline = try pipeline("Overlay/Quad", vertex: "overlayQuadVertex", fragment: "overlayQuadFragment", format: Self.colorFormat, depth: true)
        sliderPrepassPipeline = try pipeline(
            "Overlay/SliderPrepass", vertex: "sliderBodyVertex", fragment: nil, format: Self.colorFormat,
            depth: true, colorMask: [], blend: false,
        )
        sliderColorPipeline = try pipeline("Overlay/SliderColour", vertex: "sliderBodyVertex", fragment: "sliderBodyFragment", format: Self.colorFormat, depth: true)
        compositePipeline = try pipeline(
            "Overlay/Composite", vertex: "compositeVertex", fragment: "compositeFragment",
            format: drawablePixelFormat, depth: false,
        )

        func depthState(_ compare: MTLCompareFunction, write: Bool) throws -> MTLDepthStencilState {
            let descriptor = MTLDepthStencilDescriptor()
            descriptor.depthCompareFunction = compare
            descriptor.isDepthWriteEnabled = write
            guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
                throw RendererError.pipelineCreationFailed("Overlay/DepthState")
            }
            return state
        }
        prepassDepth = try depthState(.less, write: true)
        colorDepth = try depthState(.equal, write: false)
        noDepth = try depthState(.always, write: false)
    }

    /// Compiled apart from the storyboard's library, with invariance preserved:
    /// the prepass and the colour pass use the same vertex function but are two
    /// pipelines, and `equal` only holds if both produce the same depth to the
    /// bit. Built only when the overlay is first used.
    private static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        guard let url = Bundle.module.url(forResource: "Shaders", withExtension: "metal") else {
            throw RendererError.shaderLibraryUnavailable
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        let options = MTLCompileOptions()
        options.preserveInvariance = true
        do {
            return try device.makeLibrary(source: source, options: options)
        } catch {
            throw RendererError.shaderCompilationFailed(String(describing: error))
        }
    }

    /// Drops the offscreen targets (the big allocation) when the overlay goes off.
    func releaseTargets() {
        colorTarget = nil
        depthTarget = nil
        instanceBuffers = [nil, nil, nil]
        vertexBuffers = [nil, nil, nil]
    }

    /// Encodes the overlay for one frame into `commandBuffer`.
    ///
    /// - Parameters:
    ///   - frame: objects on screen, latest first.
    ///   - projection: the storyboard pass's projection; the wide-canvas margin
    ///     is added here.
    ///   - frameSlot: 0..<3, the renderer's in-flight slot, so a buffer is not
    ///     rewritten while the GPU still reads it.
    func encode(
        into commandBuffer: MTLCommandBuffer,
        frame: [ObjectVisual],
        map: GameplayMap,
        time: Double,
        target: MTLTexture,
        projection: matrix_float4x4,
        widescreen: Bool,
        frameSlot: Int,
    ) {
        let plan = OverlayPlan.build(frame)
        guard !plan.isEmpty else { return }
        guard ensureTargets(width: target.width, height: target.height),
              let colorTarget, let depthTarget
        else { return }

        let slot = frameSlot % instanceBuffers.count
        let meshes: [Int: (vertices: [SliderMeshVertex], offset: Int)] = uploadMeshes(plan: plan, map: map, time: time, slot: slot)
        guard uploadInstances(plan.instances, slot: slot) else { return }

        let overlayProjection = OverlayProjection.matrix(base: projection, widescreen: widescreen)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = colorTarget
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.depthAttachment.texture = depthTarget
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "GameplayOverlay"
        // A mesh has no winding guarantee.
        encoder.setCullMode(.none)

        func uniforms(for object: OverlayPlan.Object?) -> OverlayDrawUniforms {
            plan.uniforms(for: object, projection: overlayProjection)
        }

        func drawQuads(_ range: Range<Int>, _ buffer: MTLBuffer, _ values: inout OverlayDrawUniforms) {
            guard !range.isEmpty else { return }
            encoder.setDepthStencilState(noDepth)
            encoder.setRenderPipelineState(quadPipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: Int(BufferIndexOverlayInstances.rawValue))
            encoder.setVertexBytes(&values, length: MemoryLayout<OverlayDrawUniforms>.stride, index: Int(BufferIndexUniforms.rawValue))
            encoder.setFragmentBytes(&values, length: MemoryLayout<OverlayDrawUniforms>.stride, index: Int(BufferIndexUniforms.rawValue))
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: range.count, baseInstance: range.lowerBound)
        }

        guard let instanceBuffer = instanceBuffers[slot] else { encoder.endEncoding(); return }

        for object in plan.objects {
            var values = uniforms(for: object)
            if object.isSlider, let mesh = meshes[object.objectIndex], let vertexBuffer = vertexBuffers[slot], !mesh.vertices.isEmpty {
                encoder.setVertexBuffer(
                    vertexBuffer, offset: mesh.offset * MemoryLayout<SliderVertex>.stride,
                    index: Int(BufferIndexSliderVertices.rawValue),
                )
                encoder.setVertexBytes(&values, length: MemoryLayout<OverlayDrawUniforms>.stride, index: Int(BufferIndexUniforms.rawValue))
                encoder.setFragmentBytes(&values, length: MemoryLayout<OverlayDrawUniforms>.stride, index: Int(BufferIndexUniforms.rawValue))

                encoder.setDepthStencilState(prepassDepth)
                encoder.setRenderPipelineState(sliderPrepassPipeline)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertices.count)

                encoder.setDepthStencilState(colorDepth)
                encoder.setRenderPipelineState(sliderColorPipeline)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertices.count)
            }
            drawQuads(object.instances, instanceBuffer, &values)
        }
        var approachValues = uniforms(for: nil)
        drawQuads(plan.approach, instanceBuffer, &approachValues)
        encoder.endEncoding()

        // Composite over the drawable, keeping what the storyboard drew.
        let composite = MTLRenderPassDescriptor()
        composite.colorAttachments[0].texture = target
        composite.colorAttachments[0].loadAction = .load
        composite.colorAttachments[0].storeAction = .store
        guard let compositeEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: composite) else { return }
        compositeEncoder.label = "GameplayOverlayComposite"
        compositeEncoder.setRenderPipelineState(compositePipeline)
        compositeEncoder.setFragmentTexture(colorTarget, index: 0)
        compositeEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        compositeEncoder.endEncoding()

        passCount += 1
    }

    // ─── Resources ───────────────────────────────────────────────────────────

    private func ensureTargets(width: Int, height: Int) -> Bool {
        let current = colorTarget.map { (width: $0.width, height: $0.height) }
        guard OverlayTargetSize.needsRecreate(current: current, drawable: (width, height)) else { return true }
        guard width > 0, height > 0 else { return false }

        func make(_ format: MTLPixelFormat, usage: MTLTextureUsage, label: String) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: width, height: height, mipmapped: false,
            )
            descriptor.usage = usage
            descriptor.storageMode = .private
            let texture = device.makeTexture(descriptor: descriptor)
            texture?.label = label
            return texture
        }
        guard let color = make(Self.colorFormat, usage: [.renderTarget, .shaderRead], label: "Overlay/Colour"),
              let depth = make(Self.depthFormat, usage: .renderTarget, label: "Overlay/Depth")
        else { return false }
        colorTarget = color
        depthTarget = depth
        targetBuildCount += 1
        return true
    }

    private func uploadInstances(_ instances: [OverlayQuadInstance], slot: Int) -> Bool {
        let needed = max(instances.count, 1) * MemoryLayout<OverlayQuadInstance>.stride
        if (instanceBuffers[slot]?.length ?? 0) < needed {
            instanceBuffers[slot] = device.makeBuffer(length: needed * 2, options: .storageModeShared)
        }
        guard let buffer = instanceBuffers[slot] else { return false }
        instances.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            buffer.contents().copyMemory(from: base, byteCount: source.count)
        }
        return true
    }

    /// Concatenates the visible sliders' meshes (cached on the CPU by the map)
    /// into one buffer for this frame slot.
    private func uploadMeshes(
        plan: OverlayPlan, map: GameplayMap, time: Double, slot: Int,
    ) -> [Int: (vertices: [SliderMeshVertex], offset: Int)] {
        var meshes: [Int: (vertices: [SliderMeshVertex], offset: Int)] = [:]
        var total = 0
        for object in plan.objects where object.isSlider {
            guard let mesh = map.mesh(forObject: object.objectIndex, at: time) else { continue }
            meshes[object.objectIndex] = (mesh, total)
            total += mesh.count
        }
        guard total > 0 else { return meshes }

        let needed = total * MemoryLayout<SliderVertex>.stride
        if (vertexBuffers[slot]?.length ?? 0) < needed {
            vertexBuffers[slot] = device.makeBuffer(length: needed * 2, options: .storageModeShared)
        }
        guard let buffer = vertexBuffers[slot] else { return [:] }
        for entry in meshes.values {
            entry.vertices.withUnsafeBytes { source in
                guard let base = source.baseAddress else { return }
                (buffer.contents() + entry.offset * MemoryLayout<SliderVertex>.stride).copyMemory(from: base, byteCount: source.count)
            }
        }
        return meshes
    }
}
