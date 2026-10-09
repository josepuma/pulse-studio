import StoryboardCore
import Testing

@testable import StoryboardRendering

@Suite("Playfield canvas mapping")
struct PlayfieldCanvasMappingTests {
    @Test("Core's wide-canvas margin is the renderer's (S1.9c)")
    func marginMatchesCanvas() {
        #expect(PlayfieldMapping.wideCanvasXOffset == Double(OsuCanvas.xOffset))
    }

    @Test("the playfield centre lands inside the wide canvas, centred on x")
    func centred() {
        let centre = PlayfieldMapping.canvas(PlayfieldPoint(x: 256, y: 192))
        #expect(centre.x == Double(OsuCanvas.width) / 2)
        #expect(centre.x - 256 - PlayfieldMapping.origin.x == Double(OsuCanvas.xOffset))
    }
}
