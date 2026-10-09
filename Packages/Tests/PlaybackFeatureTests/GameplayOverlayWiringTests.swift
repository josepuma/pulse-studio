import Foundation
import Testing
import StoryboardCore
import StoryboardRendering
@testable import PlaybackFeature

/// The overlay is a way of looking, so nothing that ships — the `.osb`, the
/// project file, the video — may be able to tell it is on. These guards read
/// the wiring itself, since a GPU frame cannot say where a property is set.
@Suite("Gameplay overlay wiring")
struct GameplayOverlayWiringTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")

    private func text(_ relative: String) throws -> String {
        try String(contentsOf: Self.sources.appendingPathComponent(relative), encoding: .utf8)
    }

    @Test("the renderer is handed the overlay in exactly one place, the draw callback (R2.1)")
    func assignedOnlyInDraw() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.sources.appendingPathComponent("PlaybackFeature"), includingPropertiesForKeys: nil,
        ).filter { $0.pathExtension == "swift" }
        var assignments: [(String, String)] = []
        for file in files {
            let body = try String(contentsOf: file, encoding: .utf8)
            for line in body.split(separator: "\n") where line.contains(".gameplay =") {
                assignments.append((file.lastPathComponent, String(line)))
            }
        }
        #expect(assignments.count == 1, "found \(assignments)")
        #expect(assignments.first?.0 == "MetalCanvasView.swift")

        let canvas = try text("PlaybackFeature/MetalCanvasView.swift")
        let draw = try #require(canvas.range(of: "func draw(in view: MTKView)"))
        let tail = String(canvas[draw.upperBound...])
        let upper = tail.range(of: "\n        }\n    }\n}")?.lowerBound ?? tail.endIndex
        #expect(String(tail[..<upper]).contains("renderer.gameplay ="), "set outside draw(in:)")
    }

    @Test("the toggle is not a clock reader (S2.2d)")
    func controlsDoNotReadTheClock() throws {
        let controls = try text("PlaybackFeature/GameplayOverlayControls.swift")
        for name in ["currentTime", "observedPlayheadTime", "playheadTime", "advance(", "TimelineView", "Timer"] {
            #expect(!controls.contains(name), "the overlay controls mention \(name)")
        }
    }

    @Test("a shortcut on the overlay controls carries a modifier, so it never eats typing")
    func shortcutNeedsModifier() throws {
        let controls = try text("PlaybackFeature/GameplayOverlayControls.swift")
        let shortcuts = controls.split(separator: "\n").filter { $0.contains(".keyboardShortcut(") }
        #expect(!shortcuts.isEmpty)
        for line in shortcuts {
            #expect(line.contains("modifiers:") && line.contains(".command"), "bare shortcut: \(line)")
        }
    }

    @Test("the overlay controls use design tokens, no literal sizes")
    func tokensOnly() throws {
        let controls = try text("PlaybackFeature/GameplayOverlayControls.swift")
        let literal = try Regex(#"(width|height|spacing|padding|size|cornerRadius|opacity)\s*:\s*\(?-?\d"#)
        let hits = controls.split(separator: "\n").filter { $0.firstMatch(of: literal) != nil }
        #expect(hits.isEmpty, "literal values: \(hits)")
        #expect(!controls.contains(".font(.system"))
    }

    // ─── Nothing that ships can see it ───────────────────────────────────────

    private func document() -> EffectDocument { EffectDocument() }

    @MainActor
    private func enabledModel() async -> PlaybackModel {
        let model = PlaybackModel()
        model.connectGameplay(
            difficulties: [GameplayDifficultyOption(path: "a.osu", name: "A (timing)")],
            defaultPath: "a.osu",
            loader: { _ in
                GameplayMap(OsuGameplayParser.parse("[HitObjects]\n256,192,1000,1,0"))
            },
        )
        model.showsGameplayOverlay = true
        await model.settledGameplay()
        return model
    }

    private var sprites: [StoryboardSprite] {
        OsbParser.parse("Sprite,Foreground,Centre,\"sb/x.png\",320,240\n F,0,0,1000,0,1\n").sprites
    }

    @MainActor
    @Test("the exported .osb is byte for byte the same with the overlay on or off (S2.1b)")
    func osbBytesUnchanged() async throws {
        let off = StoryboardExport.prepareUsingAppImages(sprites, beatmapImage: { _ in Data([1]) })
        let model = await enabledModel()
        #expect(model.gameplayMap != nil, "the overlay did not load, so this compares nothing")
        let on = StoryboardExport.prepareUsingAppImages(sprites, beatmapImage: { _ in Data([1]) })
        #expect(on.storyboard == off.storyboard)
        #expect(on.images == off.images)
        #expect(!off.storyboard.isEmpty)
    }

    @MainActor
    @Test("the project file carries no trace of the overlay (S2.1c)")
    func aesbHasNoOverlayState() async throws {
        let off = try ProjectFile.encode(Project(document: document()))
        let model = await enabledModel()
        #expect(model.showsGameplayOverlay)
        let on = try ProjectFile.encode(Project(document: document()))
        #expect(on == off)

        let json = try #require(String(data: on, encoding: .utf8)).lowercased()
        for word in ["overlay", "gameplay", "difficulty"] {
            #expect(!json.contains(word), "the project file mentions \(word)")
        }
    }

    @Test("the export and the project format never name the overlay")
    func formatsDoNotKnowIt() throws {
        for file in ["StoryboardRendering/StoryboardExport.swift", "StoryboardCore/Effects/Project.swift"] {
            let body = try text(file).lowercased()
            #expect(!body.contains("gameplay") && !body.contains("overlay"), "\(file) knows about the overlay")
        }
    }
}
