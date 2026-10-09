import Foundation
import Testing

@testable import StoryboardCore

/// OPEN (pending the user's osu! stable capture, task 3.1): `verticalOffset`
/// is PROVISIONAL (0). These tests pin only the verified baseline, the
/// (64, 48) centring of a 512x384 playfield inside the 640x480 storyboard
/// space. They deliberately do NOT assert that 0 is osu!'s true vertical
/// offset, and there is no pinned-capture test yet.
@Suite("Playfield mapping")
struct PlayfieldMappingTests {
    @Test("the playfield corners land on the centred 640x480 baseline (S1.9a)")
    func baseline() {
        let topLeft = PlayfieldMapping.storyboard(PlayfieldPoint(x: 0, y: 0))
        let bottomRight = PlayfieldMapping.storyboard(PlayfieldPoint(x: 512, y: 384))
        // The vertical term is whatever the provisional constant says, so the
        // expectation is written in terms of it instead of a magic number.
        #expect(topLeft == PlayfieldPoint(x: 64, y: 48 + PlayfieldMapping.verticalOffset))
        #expect(bottomRight == PlayfieldPoint(x: 576, y: 432 + PlayfieldMapping.verticalOffset))
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
