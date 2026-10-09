import Foundation
import StoryboardCore
import StoryboardShaderTypes
import Testing
import simd

@testable import StoryboardRendering

/// The layout half of the overlay's shader contract. Kept apart from
/// `ShaderLayoutTests` because that suite is skipped on CI (it compiles the
/// shader on a GPU); nothing here needs one, so CI still catches a desync.
@Suite("Overlay shader layout")
struct OverlayShaderLayoutTests {
    private func shaderSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/StoryboardRendering/Shaders.metal")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("OverlayQuadInstance matches the shader's layout (S2.3d)")
    func quadInstance() {
        #expect(MemoryLayout<OverlayQuadInstance>.stride == 48)
        #expect(MemoryLayout<OverlayQuadInstance>.alignment == 16)
        #expect(MemoryLayout<OverlayQuadInstance>.offset(of: \.position) == 0)
        #expect(MemoryLayout<OverlayQuadInstance>.offset(of: \.radius) == 8)
        #expect(MemoryLayout<OverlayQuadInstance>.offset(of: \.alpha) == 12)
        #expect(MemoryLayout<OverlayQuadInstance>.offset(of: \.color) == 16)
        #expect(MemoryLayout<OverlayQuadInstance>.offset(of: \.angle) == 32)
        #expect(MemoryLayout<OverlayQuadInstance>.offset(of: \.progress) == 36)
        #expect(MemoryLayout<OverlayQuadInstance>.offset(of: \.kind) == 40)
    }

    @Test("SliderVertex is three packed floats and matches the CPU mesh vertex")
    func sliderVertex() {
        #expect(MemoryLayout<SliderVertex>.stride == 12)
        #expect(MemoryLayout<SliderVertex>.offset(of: \.x) == 0)
        #expect(MemoryLayout<SliderVertex>.offset(of: \.y) == 4)
        #expect(MemoryLayout<SliderVertex>.offset(of: \.distance) == 8)
        // The mesh is copied to the GPU as raw bytes.
        #expect(MemoryLayout<SliderMeshVertex>.stride == MemoryLayout<SliderVertex>.stride)
        #expect(MemoryLayout<SliderMeshVertex>.offset(of: \.x) == 0)
        #expect(MemoryLayout<SliderMeshVertex>.offset(of: \.y) == 4)
        #expect(MemoryLayout<SliderMeshVertex>.offset(of: \.d) == 8)
    }

    @Test("OverlayDrawUniforms matches the shader's layout (S2.3d)")
    func uniforms() {
        #expect(MemoryLayout<OverlayDrawUniforms>.stride == 144)
        #expect(MemoryLayout<OverlayDrawUniforms>.alignment == 16)
        #expect(MemoryLayout<OverlayDrawUniforms>.offset(of: \.projection) == 0)
        #expect(MemoryLayout<OverlayDrawUniforms>.offset(of: \.color) == 64)
        #expect(MemoryLayout<OverlayDrawUniforms>.offset(of: \.border) == 80)
        #expect(MemoryLayout<OverlayDrawUniforms>.offset(of: \.innerColor) == 96)
        #expect(MemoryLayout<OverlayDrawUniforms>.offset(of: \.slotDepth) == 112)
        #expect(MemoryLayout<OverlayDrawUniforms>.offset(of: \.slabSize) == 116)
        #expect(MemoryLayout<OverlayDrawUniforms>.offset(of: \.borderWidth) == 120)
        #expect(MemoryLayout<OverlayDrawUniforms>.offset(of: \.alpha) == 124)
        #expect(MemoryLayout<OverlayDrawUniforms>.offset(of: \.bodyOpacity) == 128)
    }

    @Test("the new buffer indices do not collide with the sprite ones")
    func bufferIndices() {
        let indices = [
            BufferIndexInstances, BufferIndexUniforms, BufferIndexOverlayInstances, BufferIndexSliderVertices,
        ].map(\.rawValue)
        #expect(Set(indices).count == indices.count)
        #expect(BufferIndexOverlayInstances.rawValue == 2)
        #expect(BufferIndexSliderVertices.rawValue == 3)
    }

    @Test("the shader mirrors the structs inline and exposes every overlay entry point")
    func sourceMirrors() throws {
        let source = try shaderSource()
        #expect(!source.contains("#include \"ShaderTypes.h\""))
        for declaration in ["struct OverlayQuadInstance", "struct SliderVertex", "struct OverlayDrawUniforms"] {
            #expect(source.contains(declaration), "\(declaration) is not mirrored in Shaders.metal")
        }
        for entry in [
            "overlayQuadVertex", "overlayQuadFragment", "sliderBodyVertex", "sliderBodyFragment",
            "compositeVertex", "compositeFragment",
        ] {
            #expect(source.contains(entry), "\(entry) is missing from Shaders.metal")
        }
        // Prepass and colour pass must agree on the depth bit for bit.
        #expect(source.contains("invariant"))
    }

    @Test("the shader's field order matches the header's (a swap would desync silently)")
    func fieldOrder() throws {
        let source = try shaderSource()
        func body(of name: String) throws -> String {
            let start = try #require(source.range(of: "struct \(name)"))
            let end = try #require(source.range(of: "};", range: start.upperBound ..< source.endIndex))
            return String(source[start.upperBound ..< end.lowerBound])
        }
        func order(_ text: String, _ names: [String]) -> [String] {
            names.compactMap { text.range(of: " \($0);").map { ($0.lowerBound, $0) } }
                .sorted { $0.0 < $1.0 }
                .map { String(text[$0.1]).trimmingCharacters(in: CharacterSet(charactersIn: " ;")) }
        }
        let quad = ["position", "radius", "alpha", "color", "angle", "progress", "kind"]
        #expect(order(try body(of: "OverlayQuadInstance"), quad) == quad)
        let uniforms = ["projection", "color", "border", "innerColor", "slotDepth", "slabSize", "borderWidth", "alpha", "bodyOpacity"]
        #expect(order(try body(of: "OverlayDrawUniforms"), uniforms) == uniforms)
        let vertex = ["x", "y", "distance"]
        #expect(order(try body(of: "SliderVertex"), vertex) == vertex)
    }
}
