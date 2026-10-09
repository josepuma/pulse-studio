import Foundation
import Testing

/// The overlay is editor-only: the frame that exports and previews share must
/// never be able to see it (S2.1a, S2.1d). A GPU test proves the pixels; this
/// proves, with no GPU, that the code path cannot even ask.
@Suite("Overlay boundary")
struct OverlayBoundaryTests {
    private func rendererSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/StoryboardRendering/MetalStoryboardRenderer.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func slice(_ source: String, from start: String, to end: String) throws -> String {
        let lower = try #require(source.range(of: start), "marker \(start) not found")
        let upper = try #require(source.range(of: end, range: lower.upperBound ..< source.endIndex), "marker \(end) not found")
        return String(source[lower.lowerBound ..< upper.lowerBound])
    }

    @Test("render(into:) and the shared render never reference the overlay")
    func sharedPathIsOverlayFree() throws {
        let source = try rendererSource()
        let publicRender = try slice(source, from: "public func render(", to: "/// The frame itself")
        let privateRender = try slice(source, from: "/// The frame itself", to: "/// Turns resolved states")
        // Make sure the slices are the right code, not empty or shifted.
        #expect(publicRender.contains("waitUntilCompleted"))
        #expect(privateRender.contains("makeRenderCommandEncoder"))
        for (name, body) in [("render(into:)", publicRender), ("render(at:into:visible:finish:)", privateRender)] {
            #expect(!body.contains("gameplay"), "\(name) reads the overlay")
            #expect(!body.lowercased().contains("overlay"), "\(name) mentions the overlay")
        }
    }

    @Test("the on-screen draw is where the overlay is encoded")
    func drawEncodesOverlay() throws {
        let source = try rendererSource()
        let draw = try slice(source, from: "public func draw(at time: Double", to: "/// Draws one frame into a texture")
        #expect(draw.contains("gameplay"))
        // Composited before the drawable is presented.
        let encode = try #require(draw.range(of: "encodeGameplay"))
        let present = try #require(draw.range(of: "commandBuffer.present"))
        #expect(encode.lowerBound < present.lowerBound)
    }
}
