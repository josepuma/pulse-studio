import Foundation
import StoryboardCore
import Testing

@testable import PlaybackFeature

/// The beatmap's own sounds: `Sample` lines in an opened `.osb` or `.osu`.
///
/// Reported against a real map: sound effects written in the `.osb` never
/// played. The loader kept only the sprites it parsed, and the preview only
/// heard the samples placed as clips in the document.
@MainActor
@Suite("Beatmap samples")
struct BeatmapSampleTests {
    private final class Recorder {
        var fired: [String] = []
    }

    private func sample(_ time: Double, _ path: String) -> StoryboardSample {
        StoryboardSample(time: time, layer: .foreground, path: path, volume: 100)
    }

    private func loaded(beatmap: [StoryboardSample]) -> (PlaybackModel, Recorder) {
        let model = PlaybackModel()
        model.contentLoaded(name: "t", sprites: [], duration: 60_000, audioURL: nil, samples: beatmap)
        model.loopRange = 0...60_000
        let recorder = Recorder()
        model.sampleSink = { sample, _ in recorder.fired.append(sample.path) }
        model.sampleCancel = {}
        model.seek(to: 0)
        return (model, recorder)
    }

    private func play(_ model: PlaybackModel, for milliseconds: Double) {
        model.startPlayback()
        for _ in 0..<Int(milliseconds / 16) { model.advance(by: 16) }
    }

    @Test("a beatmap's samples play")
    func beatmapSamplesPlay() {
        let (model, recorder) = loaded(beatmap: [sample(200, "sfx/hit.wav")])
        play(model, for: 600)
        #expect(recorder.fired == ["sfx/hit.wav"])
    }

    @Test("the document's samples play beside the beatmap's, not instead of them")
    func documentKeepsBeatmap() {
        let (model, recorder) = loaded(beatmap: [sample(200, "sfx/hit.wav")])
        model.samplesChanged([sample(400, "clip.wav")])
        model.seek(to: 0)
        play(model, for: 700)
        #expect(recorder.fired == ["sfx/hit.wav", "clip.wav"])
    }

    @Test("emptying the document leaves the beatmap's samples")
    func emptyDocumentKeepsBeatmap() {
        let (model, recorder) = loaded(beatmap: [sample(200, "sfx/hit.wav")])
        model.samplesChanged([])
        model.seek(to: 0)
        play(model, for: 600)
        #expect(recorder.fired == ["sfx/hit.wav"])
    }

    @Test("opening another beatmap replaces its samples")
    func reloadReplaces() {
        let (model, recorder) = loaded(beatmap: [sample(200, "old.wav")])
        model.contentLoaded(name: "u", sprites: [], duration: 60_000, audioURL: nil, samples: [sample(300, "new.wav")])
        model.loopRange = 0...60_000
        model.seek(to: 0)
        play(model, for: 600)
        #expect(recorder.fired == ["new.wav"])
    }

    @Test("unloading forgets the beatmap's samples")
    func unloadForgets() {
        let (model, recorder) = loaded(beatmap: [sample(200, "sfx/hit.wav")])
        model.unload()
        model.contentLoaded(name: "u", sprites: [], duration: 60_000, audioURL: nil)
        model.loopRange = 0...60_000
        model.seek(to: 0)
        play(model, for: 600)
        #expect(recorder.fired.isEmpty)
    }

    // ─── From a folder ──────────────────────────────────────────────────────

    private func folder(_ files: [String: String]) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("beatmap-samples-\(UUID().uuidString)")
        for (path, contents) in files {
            let file = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
            )
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        return url
    }

    @Test("a folder's source lists its samples and finds their files, backslashes included")
    func sourceListsSamples() throws {
        let url = try folder([
            "map.osb": "[Events]\nSample,1500,0,\"sfx\\hit.wav\",80\n",
            "sfx/hit.wav": "x",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try BeatmapStoryboardSource(folderURL: url)

        #expect(source.samples.map(\.path) == ["sfx\\hit.wav"])
        #expect(source.samples.map(\.volume) == [80])
        #expect(source.sampleURL(for: "sfx\\hit.wav")?.lastPathComponent == "hit.wav")
        #expect(source.sampleURL(for: "../escape.wav") == nil)
    }

    @Test("a source that knows nothing of samples has none")
    func defaults() {
        let source = InMemoryStoryboardSource(displayName: "x", osb: "", images: { _ in nil })
        #expect(source.samples.isEmpty)
        #expect(source.sampleURL(for: "a.wav") == nil)
    }
}
