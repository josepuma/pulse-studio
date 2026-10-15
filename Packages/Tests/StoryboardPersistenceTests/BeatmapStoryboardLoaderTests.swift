import Foundation
import Testing

@testable import StoryboardPersistence

private struct TemporaryFolder: ~Copyable {
    let url: URL

    init(files: [String: String]) throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loader-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        for (relativePath, contents) in files {
            let fileURL = url.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private let osbWithTwoSprites = """
[Events]
Sprite,Foreground,Centre,"sb/a.png",320,240
_F,0,0,1000,0,1
Sprite,Background,Centre,"sb/b.png",320,240
_F,0,0,1000,0,1
"""

private let osuWithOneSprite = """
[General]
AudioFilename: audio.mp3

[Events]
Sprite,Overlay,Centre,"sb/c.png",320,240
_F,0,0,1000,0,1

[TimingPoints]
0,500,4,2,0,100,1,0
"""

@Suite("BeatmapStoryboardLoader")
struct BeatmapStoryboardLoaderTests {
    @Test("loads sprites from a .osb")
    func loadsFromOsb() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": osbWithTwoSprites,
            "sb/a.png": "x",
            "sb/b.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.spriteCount == 2)
        #expect(result.osbPath == "map.osb")
        #expect(result.missingImagePaths.isEmpty)
    }

    @Test("loads sprites from a .osu when no .osb exists")
    func loadsFromOsuOnly() throws {
        let temporary = try TemporaryFolder(files: [
            "easy.osu": osuWithOneSprite,
            "sb/c.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.spriteCount == 1)
        #expect(result.osbPath == nil)
        #expect(result.osuPaths == ["easy.osu"])
    }

    @Test("merges .osb and .osu events")
    func mergesBothSources() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": osbWithTwoSprites,
            "easy.osu": osuWithOneSprite,
            "sb/a.png": "x",
            "sb/b.png": "x",
            "sb/c.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.spriteCount == 3)
        #expect(result.osbPath == "map.osb")
        #expect(result.osuPaths == ["easy.osu"])
    }

    @Test("only one difficulty's events are used")
    func doesNotStackEveryDifficulty() throws {
        // osu! plays one difficulty at a time, so only its events sit on the
        // shared `.osb`. Merging every difficulty draws the same sprite once
        // per file — several copies of a semi-transparent PNG stacked on
        // themselves, which reads as artwork far more saturated than the file.
        let temporary = try TemporaryFolder(files: [
            "map.osb": osbWithTwoSprites,
            "easy.osu": osuWithOneSprite,
            "normal.osu": osuWithOneSprite,
            "hard.osu": osuWithOneSprite,
            "sb/a.png": "x",
            "sb/b.png": "x",
            "sb/c.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        // Two from the `.osb`, one from a single difficulty — not one each.
        #expect(result.spriteCount == 3)
        #expect(result.osuPaths.count == 1)
    }

    @Test("sprite ids stay unique after merging")
    func idsAreUniqueAfterMerge() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": osbWithTwoSprites,
            "easy.osu": osuWithOneSprite,
            "sb/a.png": "x",
            "sb/b.png": "x",
            "sb/c.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        // Each parser numbers sprites from zero, so ids must be reassigned.
        #expect(Set(result.sprites.map(\.id)).count == result.spriteCount)
    }

    @Test("reports images the folder is missing")
    func reportsMissingImages() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": osbWithTwoSprites,
            "sb/a.png": "x",
            // sb/b.png is deliberately absent.
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.spriteCount == 2)
        #expect(result.missingImagePaths == ["sb/b.png"])
    }

    @Test("a .osu with no events does not count as a source")
    func osuWithoutEventsIsIgnored() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": osbWithTwoSprites,
            "empty.osu": "[General]\nAudioFilename: a.mp3\n",
            "sb/a.png": "x",
            "sb/b.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.osuPaths.isEmpty)
    }

    // ─── Empty storyboards ───────────────────────────────────────────────────
    //
    // An empty storyboard is where a new one starts, not a failure. Refusing
    // these folders would leave the editor able to open only work that had
    // already been done somewhere else.

    @Test("a folder with audio but no storyboard loads empty")
    func audioOnlyLoadsEmpty() throws {
        let temporary = try TemporaryFolder(files: ["audio.mp3": "x"])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.sprites.isEmpty)
        #expect(result.audioURL?.lastPathComponent == "audio.mp3")
    }

    /// The folder someone opens to write a storyboard from scratch.
    @Test("a folder with a difficulty and audio loads empty, keeping its timing")
    func difficultyAndAudioLoadEmpty() throws {
        let temporary = try TemporaryFolder(files: [
            "hard.osu": "[General]\nAudioFilename: audio.mp3\n\n[TimingPoints]\n0,500,4,2,0,100,1,0\n",
            "audio.mp3": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.sprites.isEmpty)
        #expect(result.timing != nil)
        #expect(result.audioURL?.lastPathComponent == "audio.mp3")
    }

    @Test("a folder with a difficulty and no audio still loads")
    func difficultyOnlyLoads() throws {
        let temporary = try TemporaryFolder(files: [
            "hard.osu": "[General]\nAudioFilename: missing.mp3\n",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.sprites.isEmpty)
        #expect(result.audioURL == nil)
    }

    /// Still refused: nothing to build against is the wrong folder, not an
    /// empty project.
    @Test("a folder with neither a difficulty nor audio throws")
    func unrelatedFolderThrows() throws {
        let temporary = try TemporaryFolder(files: ["notes.txt": "x"])
        let folder = try BeatmapFolder(url: temporary.url)

        #expect(throws: BeatmapFolderError.self) {
            try BeatmapStoryboardLoader.load(from: folder)
        }
    }

    // ─── Audio and timing ────────────────────────────────────────────────────

    @Test("resolves the audio file named by the .osu")
    func resolvesAudioFromOsu() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": osbWithTwoSprites,
            "easy.osu": osuWithOneSprite,
            "audio.mp3": "x",
            "sb/a.png": "x",
            "sb/b.png": "x",
            "sb/c.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.audioURL?.lastPathComponent == "audio.mp3")
        #expect(result.timing?.audioFilename == "audio.mp3")
    }

    @Test("falls back to scanning for audio when the .osu names none")
    func fallsBackToScanningForAudio() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": osbWithTwoSprites,
            "song.ogg": "x",
            "sb/a.png": "x",
            "sb/b.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.audioURL?.lastPathComponent == "song.ogg")
    }

    @Test("a folder with no audio still loads")
    func loadsWithoutAudio() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": osbWithTwoSprites,
            "sb/a.png": "x",
            "sb/b.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.audioURL == nil)
        #expect(result.spriteCount == 2)
    }

    @Test("reads timing from the .osu")
    func readsTiming() throws {
        let temporary = try TemporaryFolder(files: [
            "easy.osu": osuWithOneSprite,
            "audio.mp3": "x",
            "sb/c.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.timing?.uninheritedPoints.first?.bpm == 120)
    }

    @Test("audio resolves regardless of filename case")
    func audioResolvesCaseInsensitively() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": osbWithTwoSprites,
            // The .osu names "audio.mp3"; the file on disk is capitalised.
            "easy.osu": "[General]\nAudioFilename: audio.mp3\n",
            "Audio.MP3": "x",
            "sb/a.png": "x",
            "sb/b.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.audioURL?.lastPathComponent == "Audio.MP3")
    }
}

@Suite("Loader animation frames")
struct LoaderAnimationFrameTests {
    private let osb = """
    [Events]
    Animation,Foreground,Centre,"sb/f.png",320,240,3,100,LoopForever
    _F,0,0,1000,0,1
    """

    @Test("a missing frame is reported by its own path, not the base")
    func reportsMissingFrames() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": osb,
            "sb/f0.png": "x",
            "sb/f2.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.missingImagePaths == ["sb/f1.png"])
    }

    @Test("all frames present reports nothing")
    func allPresent() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": osb, "sb/f0.png": "x", "sb/f1.png": "x", "sb/f2.png": "x",
        ])
        let result = try BeatmapStoryboardLoader.load(from: BeatmapFolder(url: temporary.url))

        #expect(result.missingImagePaths.isEmpty)
    }
}
