import Foundation
import StoryboardCore
import Testing

@testable import StoryboardRendering

/// An animated sprite names one base path and draws many files; the export has
/// to ship every one of them, and every one of them is derived from a path
/// somebody else wrote.
@Suite("Storyboard export of animations")
struct StoryboardExportAnimationTests {
    private func animated(
        _ path: String, frames: Int = 4, id: String = "a",
    ) -> StoryboardSprite {
        StoryboardSprite(
            id: id, layer: .foreground, origin: .centre,
            filePath: path, defaultX: 0, defaultY: 0,
            animation: SpriteAnimation(frameCount: frames, frameDelay: 100, loopType: .loopForever),
        )
    }

    /// One distinct byte per frame, so a wrong file cannot pass for the right one.
    private func bytes(_ path: String) -> Data { Data(path.utf8) }

    @Test("every frame of an animation is copied, and the base path stays as named")
    func copiesEveryFrame() {
        let result = StoryboardExport.prepare(
            [animated("sb/a.png")],
            imageData: { bytes($0) },
        )

        #expect(Set(result.images.keys) == ["sb/a0.png", "sb/a1.png", "sb/a2.png", "sb/a3.png"])
        for (path, data) in result.images { #expect(data == bytes(path)) }
        #expect(result.storyboard.contains("\"sb/a.png\""))
    }

    @Test("a frame shared by several sprites is asked for once")
    func eachFrameOnce() {
        var asked: [String] = []
        _ = StoryboardExport.prepare(
            [animated("sb/a.png", id: "a"), animated("sb/a.png", id: "b")],
            imageData: { asked.append($0); return bytes($0) },
        )

        #expect(asked.sorted() == ["sb/a0.png", "sb/a1.png", "sb/a2.png", "sb/a3.png"])
    }

    @Test("an unreadable frame keeps the line and copies nothing for it")
    func unreadableFrame() {
        let result = StoryboardExport.prepare(
            [animated("sb/a.png")],
            imageData: { $0 == "sb/a2.png" ? nil : bytes($0) },
        )

        #expect(Set(result.images.keys) == ["sb/a0.png", "sb/a1.png", "sb/a3.png"])
        #expect(result.storyboard.contains("Animation,"))
        #expect(result.storyboard.contains("\"sb/a.png\""))
    }

    @Test("a hostile base path derives no frame that is read or written outside export/")
    func hostileBase() throws {
        let root = URL(fileURLWithPath: "/export-root", isDirectory: true)
        for base in ["../x.png", "..\\x.png", "a/../../x.png", "/tmp/pulse-abs.png"] {
            var asked: [String] = []
            let result = StoryboardExport.prepare(
                [animated(base)],
                imageData: { asked.append($0); return bytes($0) },
            )
            // Inserting the frame number before every dot also breaks up a
            // `..`, so some derived paths stay harmless inside the folder;
            // what must hold is that NOTHING asked for or shipped escapes it.
            for path in asked + Array(result.images.keys) {
                #expect(StoryboardExport.contained(path, in: root) != nil, "base \(base) leaked \(path)")
            }
            #expect(Set(asked) == Set(result.images.keys))
        }

        // An absolute base derives absolute frames: none is requested.
        var askedAbsolute: [String] = []
        let absolute = StoryboardExport.prepare(
            [animated("/tmp/pulse-abs.png")],
            imageData: { askedAbsolute.append($0); return bytes($0) },
        )
        #expect(askedAbsolute.isEmpty)
        #expect(absolute.images.isEmpty)
    }

    @Test("a frame the writer would refuse is skipped without aborting the rest")
    func writeSkipsUncontained() throws {
        let parent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("export-anim-\(UUID().uuidString)", isDirectory: true)
        let folder = parent.appendingPathComponent("beatmap", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let result = StoryboardExport.Result(
            storyboard: "",
            images: ["../escape0.png": Data([1]), "sb/a1.png": Data([2])],
            audio: [:],
        )
        try StoryboardExport.write(result, toFolder: folder, named: "map")

        // `../` from export/ lands in the beatmap folder itself.
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("escape0.png").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("export/sb/a1.png").path))
    }

    @Test("a hostile frame count is bounded by the cap")
    func countCapped() {
        var asked = 0
        let result = StoryboardExport.prepare(
            [animated("sb/a.png", frames: 100_000)],
            imageData: { asked += 1; return bytes($0) },
        )

        #expect(asked == AnimationFrames.maximumFrameCount)
        #expect(result.images.count == AnimationFrames.maximumFrameCount)
    }

    @Test("a built-in animation is left as named: generated frames are out of scope")
    func builtInLeftAlone() {
        var asked: [String] = []
        let result = StoryboardExport.prepare(
            [animated("__builtin__/soft.png")],
            imageData: { asked.append($0); return bytes($0) },
        )

        #expect(asked.isEmpty)
        #expect(result.images.isEmpty)
        #expect(result.storyboard.contains("\"__builtin__/soft.png\""))
    }

    @Test("a plain sprite is exported exactly as before")
    func plainUnchanged() {
        let plain = StoryboardSprite(
            id: "p", layer: .foreground, origin: .centre,
            filePath: "sb/p.png", defaultX: 0, defaultY: 0,
        )
        let result = StoryboardExport.prepare([plain], imageData: { bytes($0) })

        #expect(Set(result.images.keys) == ["sb/p.png"])
        #expect(!result.storyboard.contains("Animation,"))
    }
}
