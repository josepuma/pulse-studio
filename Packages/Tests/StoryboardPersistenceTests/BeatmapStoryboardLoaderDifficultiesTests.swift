import Foundation
import Testing

@testable import StoryboardPersistence

private func difficulty(version: String, sprite: Bool = false, readable: Bool = true) -> String {
    guard readable else { return "this is not a beatmap at all" }
    var text = "[General]\nAudioFilename: audio.mp3\n\n[Metadata]\nVersion:\(version)\n\n"
    if sprite {
        text += "[Events]\nSprite,Foreground,Centre,\"sb/c.png\",320,240\n_F,0,0,1000,0,1\n\n"
    }
    text += "[TimingPoints]\n0,500,4,2,0,100,1,0\n"
    return text
}

private func makeFolder(_ files: [String: String]) throws -> (url: URL, folder: BeatmapFolder) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("loader-difficulties-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    for (path, contents) in files {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }
    return (url, try BeatmapFolder(url: url))
}

@Suite("BeatmapStoryboardLoader difficulties")
struct BeatmapStoryboardLoaderDifficultiesTests {
    @Test("every readable difficulty is listed in loader order and the first is the default (S1.10a)")
    func listsAll() throws {
        let (url, folder) = try makeFolder([
            "a.osu": difficulty(version: "Easy"),
            "b.osu": difficulty(version: "Normal"),
            "c.osu": difficulty(version: "Hard"),
            "audio.mp3": "x",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try BeatmapStoryboardLoader.load(from: folder)
        #expect(result.difficulties.map(\.path) == ["a.osu", "b.osu", "c.osu"])
        #expect(result.difficulties.map(\.version) == ["Easy", "Normal", "Hard"])
        #expect(result.timingOsuPath == "a.osu")
        #expect(result.timingOsuPath == result.difficulties.first?.path)
    }

    @Test("storyboard from B, timing from A: the default is A and is named (timing) (S1.10b)")
    func timingDefault() throws {
        let (url, folder) = try makeFolder([
            "a.osu": difficulty(version: "A's Version"),
            "b.osu": difficulty(version: "B's Version", sprite: true),
            "sb/c.png": "x",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try BeatmapStoryboardLoader.load(from: folder)
        #expect(result.osuPaths == ["b.osu"])
        #expect(result.timingOsuPath == "a.osu")
        #expect(result.timingDifficultyName == "A's Version (timing)")
    }

    @Test("sprites and timing are what they were before the list existed (S1.10c)")
    func unchanged() throws {
        let (url, folder) = try makeFolder([
            "a.osu": difficulty(version: "A"),
            "b.osu": difficulty(version: "B", sprite: true),
            "sb/c.png": "x",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try BeatmapStoryboardLoader.load(from: folder)
        #expect(result.spriteCount == 1)
        #expect(result.sprites.first?.filePath == "sb/c.png")
        #expect(result.timing?.metadata.version == "A")
        #expect(result.audioURL == nil || result.audioURL?.lastPathComponent == "audio.mp3")
    }

    @Test("a malformed .osu is left out silently and never becomes the default (S1.10d)")
    func malformedExcluded() throws {
        let (url, folder) = try makeFolder([
            "a.osu": difficulty(version: "", readable: false),
            "b.osu": difficulty(version: "Good"),
            "audio.mp3": "x",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try BeatmapStoryboardLoader.load(from: folder)
        #expect(result.difficulties.map(\.path) == ["b.osu"])
        #expect(result.timingOsuPath == "b.osu")
    }

    @Test("a folder without difficulties reports none")
    func none() throws {
        let (url, folder) = try makeFolder(["audio.mp3": "x"])
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try BeatmapStoryboardLoader.load(from: folder)
        #expect(result.difficulties.isEmpty)
        #expect(result.timingOsuPath == nil)
        #expect(result.timingDifficultyName == nil)
    }

    @Test("a difficulty with no Version falls back to its file name")
    func unnamed() throws {
        let (url, folder) = try makeFolder([
            "my diff.osu": "[General]\nAudioFilename: audio.mp3\n\n[TimingPoints]\n0,500,4,2,0,100,1,0\n",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try BeatmapStoryboardLoader.load(from: folder)
        #expect(result.difficulties.first?.version == "my diff")
    }
}
