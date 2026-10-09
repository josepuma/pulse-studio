import Metal
import StoryboardShaderTypes
import Testing
import simd

@testable import StoryboardRendering

/// `Shaders.metal` declares its own copies of `Uniforms` and `SpriteInstance`
/// because it is compiled from source at runtime, where no header search path
/// exists. If those declarations drift from `ShaderTypes.h`, the GPU reads the
/// instance buffer at the wrong offsets and sprites render as garbage with no
/// error anywhere — so the layouts are asserted here instead.
@Suite("Shader layout")
struct ShaderLayoutTests {
    @Test("SpriteInstance matches the layout the shader expects")
    func spriteInstanceLayout() {
        // position: float2 @ 0, halfSize: float2 @ 8, anchor: float2 @ 16,
        // rotation: float @ 24, textureIndex: uint @ 28, color: float4 @ 32,
        // uvRect: float4 @ 48 (float4 forces 16-byte alignment).
        #expect(MemoryLayout<SpriteInstance>.size == 64)
        #expect(MemoryLayout<SpriteInstance>.stride == 64)
        #expect(MemoryLayout<SpriteInstance>.alignment == 16)

        #expect(MemoryLayout<SpriteInstance>.offset(of: \.position) == 0)
        #expect(MemoryLayout<SpriteInstance>.offset(of: \.halfSize) == 8)
        #expect(MemoryLayout<SpriteInstance>.offset(of: \.anchor) == 16)
        #expect(MemoryLayout<SpriteInstance>.offset(of: \.rotation) == 24)
        #expect(MemoryLayout<SpriteInstance>.offset(of: \.textureIndex) == 28)
        #expect(MemoryLayout<SpriteInstance>.offset(of: \.color) == 32)
        #expect(MemoryLayout<SpriteInstance>.offset(of: \.uvRect) == 48)
    }

    @Test("Uniforms holds a single 4x4 matrix")
    func uniformsLayout() {
        #expect(MemoryLayout<Uniforms>.size == 64)
        #expect(MemoryLayout<Uniforms>.alignment == 16)
        #expect(MemoryLayout<Uniforms>.offset(of: \.projection) == 0)
    }

    @Test("buffer indices match the shader's attribute numbers")
    func bufferIndices() {
        #expect(BufferIndexInstances.rawValue == 0)
        #expect(BufferIndexUniforms.rawValue == 1)
    }

    @Test("the shader source compiles and exposes every entry point")
    func shaderSourceCompiles() throws {
        let device = try #require(
            MTLCreateSystemDefaultDevice(),
            "no Metal device available on this machine",
        )
        let url = try #require(
            Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
            "Shaders.metal is missing from the test bundle",
        )

        let source = try String(contentsOf: url, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)

        #expect(library.makeFunction(name: "spriteVertex") != nil)
        #expect(library.makeFunction(name: "spriteFragment") != nil)
        #expect(library.makeFunction(name: "spriteFragmentUntextured") != nil)
        for name in [
            "overlayQuadVertex", "overlayQuadFragment", "sliderBodyVertex", "sliderBodyFragment",
            "compositeVertex", "compositeFragment",
        ] {
            #expect(library.makeFunction(name: name) != nil, "\(name) is not in the compiled library")
        }
    }

    @Test("the shader declares its structs inline rather than including the header")
    func shaderIsSelfContained() throws {
        let url = try #require(Bundle.module.url(forResource: "Shaders", withExtension: "metal"))
        let source = try String(contentsOf: url, encoding: .utf8)

        // A reintroduced #include would break runtime compilation, which has no
        // header search path.
        #expect(!source.contains("#include \"ShaderTypes.h\""))
        #expect(source.contains("struct SpriteInstance"))
        #expect(source.contains("struct Uniforms"))
    }
}
