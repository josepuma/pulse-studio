import Foundation
import Testing

@testable import StoryboardCore

/// The vertical offset is pinned against a real osu! stable capture of
/// Constellations [8] at ~163.9 s: fitting six circle centres gave a uniform
/// scale, x centred (origin x 64 within ~1.3 px) and origin y of about
/// 57 storyboard px, i.e. +9 +/-1.5 over the 48 baseline. 8 is the commonly
/// cited value and is consistent with that measurement.
@Suite("Playfield mapping")
struct PlayfieldMappingTests {
    @Test("the playfield corners land on the centred 640x480 baseline (S1.9a)")
    func baseline() {
        let topLeft = PlayfieldMapping.storyboard(PlayfieldPoint(x: 0, y: 0))
        let bottomRight = PlayfieldMapping.storyboard(PlayfieldPoint(x: 512, y: 384))
        // The vertical term is whatever the named constant says, so the
        // expectation is written in terms of it instead of a magic number.
        #expect(topLeft == PlayfieldPoint(x: 64, y: 48 + PlayfieldMapping.verticalOffset))
        #expect(bottomRight == PlayfieldPoint(x: 576, y: 432 + PlayfieldMapping.verticalOffset))
    }

    @Test("the vertical offset is 8 and real captured objects land where stable drew them (S1.9b)")
    func pinnedToCapture() {
        #expect(PlayfieldMapping.verticalOffset == 8)
        // Measured storyboard positions of two real objects in the capture.
        let samples: [(PlayfieldPoint, PlayfieldPoint)] = [
            (PlayfieldPoint(x: 308, y: 228), PlayfieldPoint(x: 373.3, y: 285.3)),
            (PlayfieldPoint(x: 393, y: 134), PlayfieldPoint(x: 457, y: 191.2)),
        ]
        for (playfield, measured) in samples {
            let mapped = PlayfieldMapping.storyboard(playfield)
            #expect(abs(mapped.x - measured.x) <= 2)
            #expect(abs(mapped.y - measured.y) <= 2)
        }
    }

    @Test("the playfield is centred horizontally in 640 and its scale is 1")
    func centringAndScale() {
        #expect(PlayfieldMapping.origin.x == (640 - 512) / 2)
        let a = PlayfieldMapping.storyboard(PlayfieldPoint(x: 100, y: 100))
        let b = PlayfieldMapping.storyboard(PlayfieldPoint(x: 300, y: 250))
        #expect(b.x - a.x == 200)
        #expect(b.y - a.y == 150)
    }

    @Test("the wide canvas adds the storyboard margin on x only")
    func wideCanvas() {
        let sb = PlayfieldMapping.storyboard(PlayfieldPoint(x: 0, y: 0))
        let canvas = PlayfieldMapping.canvas(PlayfieldPoint(x: 0, y: 0))
        #expect(canvas.x == sb.x + PlayfieldMapping.wideCanvasXOffset)
        #expect(canvas.y == sb.y)
    }

    @Test("no other literal playfield offset lives in the Gameplay sources")
    func singleSource() throws {
        let gameplay = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/StoryboardCore/Gameplay")
        let files = try FileManager.default.contentsOfDirectory(atPath: gameplay.path)
            .filter { $0.hasSuffix(".swift") && $0 != "PlayfieldMapping.swift" }
        #expect(files.contains("GameplayFrame.swift"))
        for file in files {
            let text = try String(contentsOf: gameplay.appendingPathComponent(file), encoding: .utf8)
            #expect(!text.contains("x: 64"), "\(file) hardcodes the playfield origin")
            #expect(!text.contains("+ 64"), "\(file) hardcodes the playfield origin")
            #expect(!text.contains("+ 48"), "\(file) hardcodes the playfield origin")
        }
    }
}
