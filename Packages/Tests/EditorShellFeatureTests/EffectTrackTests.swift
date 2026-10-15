import StoryboardCore
import Testing

@testable import EditorShellFeature

@MainActor
@Suite("Effect tracks")
struct EffectTrackTests {
    private func model() -> EditorShellModel {
        EditorShellModel()
    }

    private var descriptor: EffectDescriptor { EmitterEffect.descriptor }

    /// A parsed storyboard with one sprite on each of two layers.
    private func parsedSprites() -> [PreparedSprite] {
        let sprites = [Layer.background, .foreground].map { layer in
            StoryboardSprite(
                id: "s-\(layer.rawValue)",
                layer: layer,
                origin: .centre,
                filePath: "a.png",
                defaultX: 0,
                defaultY: 0,
                commands: [
                    Command(easing: .linear, startTime: 0, endTime: 1000, payload: .fade(start: 0, end: 1)),
                ],
            )
        }
        return StoryboardResolver.prepare(sprites)
    }

    // ─── Placing ─────────────────────────────────────────────────────────────

    @Test("adding an effect opens a track and selects the effect")
    func addingCreatesATrack() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 1000, duration: 2000)

        #expect(shell.effects.tracks.count == 1)
        #expect(shell.selectedNodeID == node.id)
        #expect(shell.selectedEffect?.id == node.id)
        #expect(shell.selectedDescriptor?.type == descriptor.type)
    }

    /// The point of the model: several effects share a lane rather than each
    /// taking a row of its own.
    @Test("further effects land on the same track")
    func effectsShareALane() {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        shell.addEffect(descriptor, at: 2000, duration: 1000)
        shell.addEffect(descriptor, at: 4000, duration: 1000)

        #expect(shell.effects.tracks.count == 1)
        #expect(shell.effects.tracks[0].nodes.count == 3)
    }

    @Test("a new effect lands on the selected track")
    func placingFollowsSelection() {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        let second = shell.addTrack()

        let node = shell.addEffect(descriptor, at: 0, duration: 1000)

        #expect(shell.effects.trackID(of: node.id) == second.id)
    }

    /// The reason the button exists: two effects can only overlap on separate
    /// lanes, so making one and dropping into it has to work in that order.
    @Test("a new track receives the next effect")
    func newTrackTakesTheNextEffect() {
        let shell = model()
        let first = shell.addEffect(descriptor, at: 1000, duration: 3000)

        let lane = shell.addTrack()
        let second = shell.addEffect(descriptor, at: 1000, duration: 3000)

        #expect(shell.effects.trackID(of: second.id) == lane.id)
        #expect(shell.effects.trackID(of: first.id) != lane.id)

        // Overlapping in time, on different lanes — which is the point.
        #expect(shell.effects[first.id]?.timeRange == shell.effects[second.id]?.timeRange)
        #expect(shell.effects.tracks.count == 2)
    }

    /// Layer tracks are gone: they were a reading of a parsed `.osb`, useful
    /// while the app could only play one back. In an editor they are rows
    /// nobody can act on.
    @Test("loading a storyboard adds no tracks of its own")
    func loadingAddsNoLayerTracks() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 1000)

        shell.load(sprites: parsedSprites(), missingImagePaths: [])

        #expect(shell.effects.tracks.count == 1)
        #expect(shell.effects.tracks[0].nodes.map(\.id) == [node.id])
        // And the assets panel stays empty, because loading a storyboard is not
        // what fills it: the list is what the *folder* holds, and the sprites
        // only say how often each file is used. A storyboard referencing the
        // app's own built-in particles must not put them in a panel they cannot
        // be dragged from.
        #expect(shell.assets.isEmpty)
    }

    @Test("removing an effect clears it from the selection")
    func removingAnEffect() {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        let second = shell.addEffect(descriptor, at: 2000, duration: 1000)

        shell.removeEffect(second.id)

        #expect(shell.effects.nodes.count == 1)
        #expect(shell.selectedNodeID == nil)
    }

    // ─── Selection ───────────────────────────────────────────────────────────

    /// Clicking a row with one clip on it and getting an empty inspector is the
    /// wrong answer to an obvious question: there is exactly one thing there to
    /// edit.
    /// A lane is not a clip.
    ///
    /// Its only effect used to answer here, so clicking the row showed that
    /// clip's parameters without clicking the clip. Convenient, and it meant
    /// the panel never emptied: after deselecting, it went on offering
    /// parameters for something nothing on screen said was chosen. A lane's
    /// own panel carries its name and layer — a clip's parameters belong to
    /// the clip.
    @Test("a lane does not stand in for the clip on it")
    func laneDoesNotStandInForItsClip() {
        let shell = model()
        _ = shell.addEffect(descriptor, at: 0, duration: 1000)

        shell.selectedNodeID = nil
        shell.selectedTrackID = shell.effects.tracks[0].id

        #expect(shell.selectedEffect == nil)
        #expect(shell.selectedTrack != nil)
    }

    /// With several, there is no single effect to edit and picking one
    /// arbitrarily would be a guess. The lane itself is the selection.
    @Test("selecting a lane with several effects edits none of them")
    func laneWithManyEffectsShowsTheLane() {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        shell.addEffect(descriptor, at: 2000, duration: 1000)

        shell.selectedNodeID = nil
        shell.selectedTrackID = shell.effects.tracks[0].id

        #expect(shell.selectedEffect == nil)
        #expect(shell.selectedTrack?.nodes.count == 2)
    }

    @Test("selecting a clip edits that clip, whatever else is on its lane")
    func selectingAClipWins() {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        let second = shell.addEffect(descriptor, at: 2000, duration: 1000)

        shell.selectedNodeID = second.id

        #expect(shell.selectedEffect?.id == second.id)
    }

    // ─── Filters ─────────────────────────────────────────────────────────────

    /// Filters belong to the clip, not the lane: a filter is dragged onto the
    /// thing it will change, and applying it to everything around that thing
    /// is a drop promising one thing and doing another.
    @Test("a filter applies to the clip it was dropped on")
    func filterBelongsToTheClip() {
        let shell = model()
        let first = shell.addEffect(descriptor, at: 0, duration: 1000)
        let second = shell.addEffect(descriptor, at: 2000, duration: 1000)

        shell.addFilter(GlowFilter.descriptor, to: first.id)

        #expect(shell.effects[first.id]?.filters.count == 1)
        #expect(shell.effects[second.id]?.filters.isEmpty == true)
    }

    /// The inspector shows a clip's filters, so applying one has to put that
    /// clip in front of whoever just dropped it.
    @Test("applying a filter selects the clip it landed on")
    func filterSelectsItsClip() {
        let shell = model()
        let first = shell.addEffect(descriptor, at: 0, duration: 1000)
        let second = shell.addEffect(descriptor, at: 2000, duration: 1000)
        shell.selectedNodeID = second.id

        shell.addFilter(GlowFilter.descriptor, to: first.id)

        #expect(shell.selectedNodeID == first.id)
        #expect(shell.selectedEffect?.filters.count == 1)
    }

    @Test("a filter reaches the clip's output")
    func filterReachesOutput() async {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 2000)
        shell.setValue(.integer(4), for: EmitterEffect.Param.count, on: node.id)

        #expect(await shell.settledSprites().count == 4)

        shell.addFilter(GlowFilter.descriptor, to: node.id)
        #expect(await shell.settledSprites().count > 4)
        #expect(shell.spriteMultiplier(for: node.id) > 1)
    }

    /// One clip's filter leaves its neighbours alone.
    @Test("a filter on one clip does not touch another")
    func filtersAreIsolated() async {
        let shell = model()
        let first = shell.addEffect(descriptor, at: 0, duration: 2000)
        let second = shell.addEffect(descriptor, at: 3000, duration: 2000)
        shell.setValue(.integer(3), for: EmitterEffect.Param.count, on: first.id)
        shell.setValue(.integer(3), for: EmitterEffect.Param.count, on: second.id)

        shell.addFilter(GlowFilter.descriptor, to: first.id)

        // Three become six on the filtered clip; the other keeps its three.
        #expect(await shell.settledSprites().count == 9)
    }

    @Test("removing a filter puts the output back")
    func removingAFilter() async {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 2000)
        shell.setValue(.integer(4), for: EmitterEffect.Param.count, on: node.id)

        let filter = shell.addFilter(GlowFilter.descriptor, to: node.id)!
        shell.removeFilter(filter.id, from: node.id)

        #expect(await shell.settledSprites().count == 4)
        #expect(shell.spriteMultiplier(for: node.id) == 1)
    }

    // ─── Editing ─

    @Test("changing a parameter re-evaluates the output")
    func parameterChangeUpdatesOutput() async {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 2000)

        shell.setValue(.integer(8), for: EmitterEffect.Param.count, on: node.id)
        #expect(await shell.settledSprites().count == 8)

        shell.setValue(.integer(30), for: EmitterEffect.Param.count, on: node.id)
        #expect(await shell.settledSprites().count == 30)
    }

    @Test("moving an effect keeps its length")
    func movingKeepsLength() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 1000, duration: 2000)

        shell.moveEffect(node.id, to: 5000)

        #expect(shell.effects[node.id]?.timeRange == 5000...7000)
    }

    @Test("an effect can be moved to another track")
    func movingBetweenTracks() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 1000)
        let destination = shell.addTrack()

        shell.moveEffect(node.id, toTrack: destination.id)

        #expect(shell.effects.trackID(of: node.id) == destination.id)
    }

    /// Hiding a lane hides what is on it — the only reading of the control that
    /// makes sense.
    @Test("hiding a track removes its effects from the output")
    func hidingATrack() async {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 2000)
        shell.setValue(.integer(10), for: EmitterEffect.Param.count, on: node.id)
        let trackID = shell.effects.tracks[0].id

        #expect(await shell.settledSprites().count == 10)

        shell.toggleVisibility(of: trackID)
        #expect(await shell.settledSprites().isEmpty)
    }

    @Test("removing a track removes what was on it")
    func removingATrack() async {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        let trackID = shell.effects.tracks[0].id

        shell.removeTrack(trackID)

        #expect(shell.effects.tracks.isEmpty)
        #expect(await shell.settledSprites().isEmpty)
        #expect(shell.selectedNodeID == nil)
    }

    // ─── Draw order ──────────────────────────────────────────────────────────

    @Test("raising a track reorders the evaluated sprites")
    func reorderingReachesTheCanvas() async {
        let shell = model()
        let first = shell.addEffect(descriptor, at: 0, duration: 2000)
        shell.addTrack()
        shell.addEffect(descriptor, at: 0, duration: 2000)

        #expect(await shell.settledSprites().first?.id.hasPrefix(first.id) == true)

        shell.raiseTrack(shell.effects.tracks[0].id)
        #expect(await shell.settledSprites().last?.id.hasPrefix(first.id) == true)
    }

    /// The bug this pins: the renderer keeps its own copy of the sprites on the
    /// GPU, uploaded once. Any change to the effects has to be observable, or
    /// the canvas cannot know to upload again.
    @Test("every change to the effects is observable")
    func everyChangeIsObservable() {
        let shell = model()
        var seen: Set<Int> = [shell.effectsRevision]

        let node = shell.addEffect(descriptor, at: 0, duration: 1000)
        seen.insert(shell.effectsRevision)

        shell.setValue(.integer(5), for: EmitterEffect.Param.count, on: node.id)
        seen.insert(shell.effectsRevision)

        shell.moveEffect(node.id, to: 2000)
        seen.insert(shell.effectsRevision)

        shell.resizeEffect(node.id, startTime: 2000, duration: 3000)
        seen.insert(shell.effectsRevision)

        shell.toggleVisibility(of: shell.effects.tracks[0].id)
        seen.insert(shell.effectsRevision)

        #expect(seen.count == 6)
    }

    /// The property the timeline drag relies on: moving a clip shifts the same
    /// particles rather than drawing new ones.
    @Test("dragging a clip shifts its sprites without changing them")
    func draggingShiftsOutput() async {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 2000)
        shell.setValue(.integer(6), for: EmitterEffect.Param.count, on: node.id)

        let before = await shell.settledSprites()
        shell.moveEffect(node.id, to: 3000)
        let after = await shell.settledSprites()

        #expect(before.count == after.count)
        for (original, moved) in zip(before, after) {
            #expect(original.defaultX == moved.defaultX)
            #expect(original.defaultY == moved.defaultY)
            for (a, b) in zip(original.commands, moved.commands) {
                #expect(b.startTime == a.startTime + 3000)
            }
        }
    }

    /// The timeline window has to cover effects placed past the storyboard, or
    /// the row drops them for being off screen — a clip vanishing mid-drag.
    @Test("the document range covers effects placed beyond the storyboard")
    func rangeGrowsWithPlacedEffects() {
        let shell = model()
        shell.load(sprites: parsedSprites(), missingImagePaths: [])
        let node = shell.addEffect(descriptor, at: 30_000, duration: 5000)

        #expect(shell.effects.timeRange?.upperBound == 35_000)
        #expect(shell.effects.timeRange?.contains(node.startTime) == true)
    }
}

/// Deleting a lane that carries work asks first.
///
/// There is no undo for this, so a track with clips is somebody's afternoon —
/// and **two** paths reach the delete: the row's menu and the Delete key. A
/// confirmation attached to one of them leaves the other destroying work in
/// silence, which is the path most easily hit by accident.
@MainActor
@Suite("Track deletion")
struct TrackDeletionTests {
    @Test("an empty track goes without asking")
    func emptyTrackDeletesOutright() {
        let shell = EditorShellModel()
        let track = shell.addTrack()

        shell.requestRemoveTrack(track.id)

        #expect(shell.trackPendingDeletion == nil, "nothing to lose, nothing to ask")
        #expect(shell.effects.track(id: track.id) == nil)
    }

    /// Confirming a delete that destroys nothing teaches people to dismiss the
    /// dialog — and then they dismiss the one that mattered too.
    @Test("a track with clips waits for confirmation")
    func populatedTrackAsksFirst() {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)
        let trackID = shell.effects.trackID(of: node.id)!

        shell.requestRemoveTrack(trackID)

        #expect(shell.trackPendingDeletion?.id == trackID)
        #expect(shell.effects.track(id: trackID) != nil, "nothing is deleted until confirmed")
        #expect(shell.clipsPendingDeletion == 1)
    }

    @Test("confirming deletes the track")
    func confirmingDeletes() {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)
        let trackID = shell.effects.trackID(of: node.id)!

        shell.requestRemoveTrack(trackID)
        shell.confirmRemoveTrack()

        #expect(shell.effects.track(id: trackID) == nil)
        #expect(shell.trackPendingDeletion == nil)
    }

    @Test("cancelling keeps the track and everything on it")
    func cancellingKeepsIt() {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)
        let trackID = shell.effects.trackID(of: node.id)!

        shell.requestRemoveTrack(trackID)
        shell.cancelRemoveTrack()

        #expect(shell.trackPendingDeletion == nil)
        #expect(shell.effects.track(id: trackID) != nil)
        #expect(shell.effects[node.id] != nil, "the clip is still there too")
    }

    /// The Delete key is the path hit by accident, so it has to ask as loudly
    /// as the menu does.
    @Test("the delete key asks too")
    func deleteKeyAsks() {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)
        let trackID = shell.effects.trackID(of: node.id)!

        // With the lane selected rather than a clip, Delete means the lane.
        shell.selectedNodeID = nil
        shell.selectedTrackID = trackID
        shell.deleteSelection()

        #expect(shell.trackPendingDeletion?.id == trackID)
        #expect(shell.effects.track(id: trackID) != nil)
    }

    /// The count, because "some clips" is not something anyone can weigh.
    @Test("the alert can say how many clips would go")
    func reportsTheClipCount() {
        let shell = EditorShellModel()
        let first = shell.addEffect(EmitterEffect.descriptor, at: 0)
        let trackID = shell.effects.trackID(of: first.id)!
        shell.addEffect(EmitterEffect.descriptor, at: 5000, on: trackID)

        shell.requestRemoveTrack(trackID)

        #expect(shell.clipsPendingDeletion == 2)
    }
}

/// The assets panel lists what the **folder holds**, not what the storyboard
/// happens to reference.
///
/// Those are different questions, and the second is the wrong one for a panel
/// called Assets: a file sitting in the folder waiting to be placed never
/// appeared, which is the one case where looking at the panel is the point. It
/// also filled with paths that are not the mapper's — the app's own built-in
/// particles and the hashed glyphs a text effect mints live inside the binary,
/// so they have no thumbnail to show and no folder to be dragged from.
@MainActor
@Suite("Assets panel")
struct AssetsPanelTests {
    @Test("an unused file in the folder still appears")
    func unusedFilesAreListed() {
        let shell = EditorShellModel()

        shell.loadFolderAssets(["sb/unused.png", "sb/used.png"])

        #expect(shell.assets.map(\.path).sorted() == ["sb/unused.png", "sb/used.png"])
    }

    /// A built-in path is the app's, not the beatmap's. It cannot be shown, and
    /// it cannot be dragged from a folder it is not in.
    @Test("built-in and generated paths never reach the panel")
    func onlyFolderFilesAreListed() {
        let shell = EditorShellModel()

        // Only the folder decides. Whatever the sprites reference — built-ins,
        // text glyphs, derived blurs — is not consulted for the list.
        shell.loadFolderAssets(["sb/real.png"])

        #expect(shell.assets.count == 1)
        #expect(shell.assets[0].path == "sb/real.png")
    }

    /// Use count still leads, because it says which files matter to this
    /// storyboard — a folder can hold dozens.
    @Test("the most used file sorts first")
    func sortsByUsage() {
        let shell = EditorShellModel()
        shell.loadFolderAssets(["sb/rare.png", "sb/common.png"])

        shell.load(
            sprites: [
                prepared(path: "sb/common.png", id: "a"),
                prepared(path: "sb/common.png", id: "b"),
                prepared(path: "sb/rare.png", id: "c"),
            ],
            missingImagePaths: [],
        )

        #expect(shell.assets.map(\.path) == ["sb/common.png", "sb/rare.png"])
        #expect(shell.assets[0].useCount == 2)
    }

    /// Every unused file has a count of zero, so without a tiebreak they come
    /// back in whatever order the file system gave — which is no order at all
    /// to anyone scanning the list.
    @Test("unused files are ordered by name, not by chance")
    func breaksTiesByName() {
        let shell = EditorShellModel()

        shell.loadFolderAssets(["sb/zebra.png", "sb/apple.png", "sb/mango.png"])

        #expect(shell.assets.map(\.name) == ["apple.png", "mango.png", "zebra.png"])
    }

    /// Where a file lives is part of what it is here.
    ///
    /// osu! reads the root for the map's own art and `sb/` for the storyboard's,
    /// so a background imported into the wrong one is broken in a way nothing
    /// shows until export — which is exactly what happened when the panel kept
    /// only the last path component and the two looked identical.
    @Test("an asset reports which folder it sits in")
    func reportsItsFolder() {
        let shell = EditorShellModel()

        shell.loadFolderAssets(["bg.jpg", "sb/particle.png", "sb/deep/spark.png"])

        let folders = Dictionary(
            uniqueKeysWithValues: shell.assets.map { ($0.path, $0.folder) },
        )
        #expect(folders["bg.jpg"] == "root")
        #expect(folders["sb/particle.png"] == "sb")
        #expect(folders["sb/deep/spark.png"] == "sb/deep")
    }

    /// Two files sharing a name in different folders are different files, and a
    /// panel that shows them identically is a panel you cannot act on.
    @Test("same name in two folders stays distinguishable")
    func sameNameDifferentFolders() {
        let shell = EditorShellModel()

        shell.loadFolderAssets(["bg.jpg", "sb/bg.jpg"])

        #expect(shell.assets.count == 2)
        #expect(Set(shell.assets.map(\.folder)) == ["root", "sb"])
    }

    /// The destination is a real fork, so each one has to name a distinct place.
    @Test("each destination maps to its own folder")
    func destinationsAreDistinct() {
        #expect(AssetDestination.root.relativeFolder == "")
        #expect(AssetDestination.storyboard.relativeFolder == "sb")
        #expect(AssetDestination.allCases.count == 2)
    }

    private func prepared(path: String, id: String) -> PreparedSprite {
        StoryboardResolver.prepare([
            StoryboardSprite(
                id: id,
                layer: .foreground,
                origin: .centre,
                filePath: path,
                defaultX: 320,
                defaultY: 240,
                commands: [Command(
                    easing: .linear,
                    startTime: 0,
                    endTime: 1000,
                    payload: .fade(start: 1, end: 1),
                )],
                loops: [],
            ),
        ])[0]
    }
}

@MainActor
@Suite("Asset usage of animation frames")
struct AnimationAssetUsageTests {
    @Test("every frame counts as used, the base path does not")
    func framesAreUsed() {
        let shell = EditorShellModel()
        shell.loadFolderAssets(["sb/f0.png", "sb/f1.png", "sb/f.png"])
        let animated = StoryboardSprite(
            id: "a", layer: .foreground, origin: .centre, filePath: "sb/f.png",
            defaultX: 0, defaultY: 0,
            commands: [Command(easing: .linear, startTime: 0, endTime: 1000, payload: .fade(start: 1, end: 1))],
            animation: SpriteAnimation(frameCount: 2, frameDelay: 100, loopType: .loopForever),
        )

        shell.load(sprites: StoryboardResolver.prepare([animated]), missingImagePaths: [])

        let uses = Dictionary(uniqueKeysWithValues: shell.assets.map { ($0.path, $0.useCount) })
        #expect(uses["sb/f0.png"] == 1)
        #expect(uses["sb/f1.png"] == 1)
        #expect(uses["sb/f.png"] == 0)
    }
}
