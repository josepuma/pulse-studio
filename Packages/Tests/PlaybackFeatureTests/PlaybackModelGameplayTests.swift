import Foundation
import Testing
import StoryboardCore
@testable import PlaybackFeature

/// Counts loader calls and records which thread each ran on.
private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var paths: [String] = []
    private(set) var ranOnMain: [Bool] = []

    func record(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        paths.append(path)
        ranOnMain.append(Thread.isMainThread)
    }

    var calls: [String] { lock.lock(); defer { lock.unlock() }; return paths }
    var mainFlags: [Bool] { lock.lock(); defer { lock.unlock() }; return ranOnMain }
}

private let easy = GameplayDifficultyOption(path: "a.osu", name: "Easy (timing)")
private let hard = GameplayDifficultyOption(path: "b.osu", name: "Hard")

/// A map whose object count says which difficulty it came from.
private func map(circles: Int) -> GameplayMap {
    let lines = (0 ..< circles).map { "256,192,\(1000 + $0 * 100),1,0" }
    let text = "[Difficulty]\nCircleSize:4\nApproachRate:9\n[TimingPoints]\n0,500,4,2,0,100,1,0\n[HitObjects]\n"
        + lines.joined(separator: "\n")
    return GameplayMap(OsuGameplayParser.parse(text))
}

@MainActor
private func connected(_ probe: Probe) -> PlaybackModel {
    let model = PlaybackModel()
    model.connectGameplay(
        difficulties: [easy, hard],
        defaultPath: "a.osu",
        loader: { path in
            probe.record(path)
            return map(circles: path == "a.osu" ? 1 : 2)
        },
    )
    return model
}

@MainActor
@Suite("Playback model gameplay overlay")
struct PlaybackModelGameplayTests {
    @Test("a fresh model has the overlay off and never calls the loader (S2.5a, S2.2a)")
    func offByDefault() async {
        let probe = Probe()
        let model = connected(probe)
        #expect(model.showsGameplayOverlay == false)
        await model.settledGameplay()
        #expect(probe.calls.isEmpty, "hit objects were parsed with the overlay never enabled")
        #expect(model.gameplayMap == nil)
    }

    @Test("the picker lists the source's difficulties with the timing one selected (S2.5b)")
    func pickerItems() {
        let model = connected(Probe())
        #expect(model.gameplayDifficulties == [easy, hard])
        #expect(model.selectedGameplayDifficultyPath == "a.osu")
        #expect(model.selectedGameplayDifficultyName == "Easy (timing)")
    }

    @Test("the first enable loads the default difficulty once, off the main thread")
    func lazyLoad() async {
        let probe = Probe()
        let model = connected(probe)
        model.showsGameplayOverlay = true
        await model.settledGameplay()
        #expect(probe.calls == ["a.osu"])
        #expect(probe.mainFlags == [false], "the parse ran on the main thread")
        #expect(model.gameplayMap?.objects.count == 1)

        // Off and on again reuses the map: the toggle is not a reload.
        model.showsGameplayOverlay = false
        model.showsGameplayOverlay = true
        await model.settledGameplay()
        #expect(probe.calls == ["a.osu"], "toggling re-parsed")
    }

    @Test("selecting another difficulty before enabling hands the renderer that one (S2.5c)")
    func selectThenEnable() async {
        let probe = Probe()
        let model = connected(probe)
        model.selectGameplayDifficulty("b.osu")
        await model.settledGameplay()
        #expect(probe.calls.isEmpty, "selecting parsed while the overlay was off")
        model.showsGameplayOverlay = true
        await model.settledGameplay()
        #expect(probe.calls == ["b.osu"])
        #expect(model.gameplayMap?.objects.count == 2)
    }

    @Test("switching difficulty while on builds a new map (S2.6b)")
    func switchWhileOn() async {
        let probe = Probe()
        let model = connected(probe)
        model.showsGameplayOverlay = true
        await model.settledGameplay()
        model.selectGameplayDifficulty("b.osu")
        await model.settledGameplay()
        #expect(probe.calls == ["a.osu", "b.osu"])
        #expect(model.gameplayMap?.objects.count == 2)
    }

    @Test("an unknown difficulty is ignored")
    func unknownDifficulty() {
        let model = connected(Probe())
        model.selectGameplayDifficulty("zzz.osu")
        #expect(model.selectedGameplayDifficultyPath == "a.osu")
    }

    @Test("opening another project resets the toggle and the choice (S2.5d)")
    func reopenResets() async {
        let probe = Probe()
        let model = connected(probe)
        model.selectGameplayDifficulty("b.osu")
        model.showsGameplayOverlay = true
        await model.settledGameplay()

        model.connectGameplay(difficulties: [easy, hard], defaultPath: "a.osu", loader: { _ in nil })
        #expect(model.showsGameplayOverlay == false)
        #expect(model.selectedGameplayDifficultyPath == "a.osu")
        #expect(model.gameplayMap == nil)
    }

    @Test("a source with no difficulties leaves nothing to enable")
    func nothingToLoad() async {
        let model = PlaybackModel()
        model.showsGameplayOverlay = true
        await model.settledGameplay()
        #expect(model.gameplayMap == nil)
        #expect(model.gameplayDifficulties.isEmpty)
    }

    @Test("a load that lands after the difficulty changed is dropped")
    func staleLoadDropped() async throws {
        // The first difficulty's parse is held until the second has landed, so
        // the order is the one that goes wrong rather than one that happens to
        // go right.
        let gate = DispatchSemaphore(value: 0)
        let model = PlaybackModel()
        model.connectGameplay(
            difficulties: [easy, hard],
            defaultPath: "a.osu",
            loader: { path in
                if path == "a.osu" { gate.wait() }
                return map(circles: path == "a.osu" ? 1 : 2)
            },
        )
        model.showsGameplayOverlay = true
        model.selectGameplayDifficulty("b.osu")
        await model.settledGameplay()
        #expect(model.gameplayMap?.objects.count == 2)

        gate.signal()
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.gameplayMap?.objects.count == 2, "an older difficulty's map won the race")
    }

    @Test("toggling touches neither the sprites nor their revision (S2.5f)")
    func togglingIsNotAnEdit() async {
        let model = connected(Probe())
        let revision = model.spritesRevision
        model.showsGameplayOverlay = true
        await model.settledGameplay()
        model.selectGameplayDifficulty("b.osu")
        model.showsGameplayOverlay = false
        #expect(model.spritesRevision == revision)
    }
}
