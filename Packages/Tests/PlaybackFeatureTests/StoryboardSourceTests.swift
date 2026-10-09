import Foundation
import Testing
import StoryboardCore
@testable import PlaybackFeature

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private func osu(version: String, objects: [String] = []) -> String {
    var text = "[General]\nAudioFilename: audio.mp3\n\n[Metadata]\nVersion:\(version)\n\n"
    text += "[Difficulty]\nCircleSize:4\nApproachRate:9\n\n[TimingPoints]\n0,500,4,2,0,100,1,0\n\n"
    text += "[HitObjects]\n" + objects.joined(separator: "\n") + "\n"
    return text
}

private func makeFolder(_ files: [String: String]) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("source-gameplay-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    for (path, contents) in files {
        try contents.write(to: url.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }
    return url
}

@Suite("Storyboard source gameplay seam")
struct StoryboardSourceTests {
    @Test("a source that knows nothing of hit objects lists none and loads none")
    func defaults() {
        let source = InMemoryStoryboardSource(displayName: "x", osb: "", images: { _ in nil })
        #expect(source.gameplayDifficulties.isEmpty)
        #expect(source.defaultGameplayDifficultyPath == nil)
        #expect(source.loadGameplay(path: "a.osu") == nil)
    }

    @Test("a beatmap lists its difficulties, names the timing one and parses none until asked (S2.5b)")
    func listsWithoutParsing() throws {
        let url = try makeFolder([
            "a.osu": osu(version: "Easy"),
            "b.osu": osu(version: "Hard", objects: ["256,192,1000,1,0"]),
            "audio.mp3": "x",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let counter = Counter()
        let source = try BeatmapStoryboardSource(folderURL: url, onGameplayParse: { counter.bump() })

        #expect(source.gameplayDifficulties.map(\.path) == ["a.osu", "b.osu"])
        #expect(source.gameplayDifficulties.map(\.name) == ["Easy (timing)", "Hard"])
        #expect(source.defaultGameplayDifficultyPath == "a.osu")
        #expect(counter.count == 0, "opening a folder parsed hit objects")

        let map = try #require(source.loadGameplay(path: "b.osu"))
        #expect(map.objects.count == 1)
        #expect(counter.count == 1)
    }

    @Test("a path that is not a listed difficulty loads nothing")
    func unlisted() throws {
        let url = try makeFolder(["a.osu": osu(version: "Easy"), "audio.mp3": "x"])
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try BeatmapStoryboardSource(folderURL: url)
        #expect(source.loadGameplay(path: "../x.osu") == nil)
        #expect(source.loadGameplay(path: "nope.osu") == nil)
    }
}
