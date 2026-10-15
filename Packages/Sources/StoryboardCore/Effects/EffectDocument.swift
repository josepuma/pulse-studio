import Foundation

/// A lane of the timeline: a name, a layer, and the effects placed along it.
///
/// A track holds many effects rather than being one, which is what lets a
/// project stay readable as it grows. One row per effect turns a storyboard
/// with thirty of them into thirty rows nobody can scan, and leaves no way to
/// say that these four belong together.
///
/// The layer lives here rather than on each effect: osu!'s layers are about
/// what draws in front of what, which is the same question a track answers.
public struct EffectTrack: Identifiable, Sendable, Equatable, Codable {
    // ─── Decoding ────────────────────────────────────────────────────────────

    private enum CodingKeys: String, CodingKey {
        case id, name, layer, nodes, isVisible, isLocked, colour, z, followsCamera
        /// A parallax factor, written by a build that had no perspective.
        /// Read once and translated; never written.
        case depth
        /// Filters used to live on the track. They belong to a clip now, but a
        /// project written before that move still has them here, and a decoder
        /// that simply failed would open a real project as an empty one.
        case filters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        layer = try container.decode(Layer.self, forKey: .layer)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        // Absent in files written before tracks could be coloured, and a track
        // without one falls back to its layer's — which is what every track
        // showed until now, so an old project opens looking as it did.
        colour = try container.decodeIfPresent(TrackColour.self, forKey: .colour)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
        // Absent in files written before the camera: Z 0, following it, is
        // what every track was.
        z = try container.decodeIfPresent(Double.self, forKey: .z) ?? 0
        followsCamera = try container.decodeIfPresent(Bool.self, forKey: .followsCamera) ?? true

        // A parallax factor from before the perspective camera. 0 meant fixed
        // to the screen; any other factor becomes the Z that pans the same —
        // a lane at Z pans by focal ÷ (focal + Z), so the factor d is
        // focal · (1/d − 1). The size now follows the distance too, which is
        // the point of the change, so a far lane also draws smaller.
        if let legacy = try container.decodeIfPresent(Double.self, forKey: .depth),
           !container.contains(.z)
        {
            if legacy <= 0 {
                followsCamera = false
            } else {
                z = CameraProperty.focal.defaultValue * (1 / legacy - 1)
            }
        }

        var decodedNodes = try container.decode([EffectNode].self, forKey: .nodes)

        // A track's filters move onto everything that was on it, which is what
        // they applied to before: the look is preserved, and the file that
        // described it opens rather than being refused.
        if let inherited = try container.decodeIfPresent([FilterNode].self, forKey: .filters),
           !inherited.isEmpty
        {
            for index in decodedNodes.indices {
                decodedNodes[index].filters = inherited + decodedNodes[index].filters
            }
        }
        nodes = decodedNodes
    }

    /// Written without `filters`, which no longer belongs to a track.
    ///
    /// Spelled out because the custom `CodingKeys` carries a key with no
    /// property behind it, and Swift will not synthesise an encoder for that.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(layer, forKey: .layer)
        try container.encode(nodes, forKey: .nodes)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encodeIfPresent(colour, forKey: .colour)
        try container.encode(isLocked, forKey: .isLocked)
        // Left out at their defaults so a project that never touched them
        // saves to the same bytes it did before they existed.
        if z != 0 { try container.encode(z, forKey: .z) }
        if !followsCamera { try container.encode(followsCamera, forKey: .followsCamera) }
    }

    public let id: String
    public var name: String
    public var layer: Layer
    public var nodes: [EffectNode]
    public var isVisible: Bool

    /// The track's own colour, or `nil` to take its layer's.
    ///
    /// Optional rather than defaulted so "never chosen" and "chosen to match
    /// the layer" stay different: a track that has not been given a colour
    /// follows its layer when that layer changes, and one that has been given
    /// a colour keeps it.
    public var colour: TrackColour?
    public var isLocked: Bool

    /// How far behind the focal plane the lane sits, in storyboard units.
    ///
    /// 0 is drawn as it always was; one focal length back (1000 by default)
    /// is half the size and pans half as far; negative is closer than the
    /// focal plane and rushes past. Size and parallax come from the one
    /// distance, which is what makes a far lane read as far rather than slow.
    ///
    /// On the lane rather than each clip because the lane is already the unit
    /// of layer and draw order, and "this row is far away" is the same kind of
    /// statement.
    public var z: Double

    /// Whether the camera applies to this lane at all. Off for lyrics or a
    /// HUD, which stay on screen wherever the camera goes.
    public var followsCamera: Bool

    public init(
        id: String,
        name: String,
        layer: Layer = .foreground,
        nodes: [EffectNode] = [],
        isVisible: Bool = true,
        colour: TrackColour? = nil,
        isLocked: Bool = false,
        z: Double = 0,
        followsCamera: Bool = true,
    ) {
        self.id = id
        self.name = name
        self.layer = layer
        self.nodes = nodes
        self.isVisible = isVisible
        self.colour = colour
        self.isLocked = isLocked
        self.z = z
        self.followsCamera = followsCamera
    }

    /// The span from the earliest effect to the latest, or `nil` when empty.
    public var timeRange: ClosedRange<Double>? {
        guard let first = nodes.first else { return nil }
        let lower = nodes.reduce(first.startTime) { min($0, $1.startTime) }
        let upper = nodes.reduce(first.endTime) { max($0, $1.endTime) }
        return lower...max(lower, upper)
    }
}

/// The placed effects that make up a storyboard, grouped into tracks.
///
/// This is what a project saves. The sprites are derived from it on every
/// evaluation and never stored — keeping the output instead would leave
/// thousands of loose commands with no way back to the emitter that wrote them.
public struct EffectDocument: Sendable, Codable {
    public var tracks: [EffectTrack]

    /// The storyboard's camera, seen through by every track at its own depth.
    public var camera: StoryboardCamera

    public init(tracks: [EffectTrack] = [], camera: StoryboardCamera = StoryboardCamera()) {
        self.tracks = tracks
        self.camera = camera
    }

    private enum CodingKeys: String, CodingKey { case tracks, camera }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try container.decode([EffectTrack].self, forKey: .tracks)
        // Absent in every file written before the camera existed.
        camera = try container.decodeIfPresent(StoryboardCamera.self, forKey: .camera) ?? StoryboardCamera()
    }

    /// Written without a camera nobody touched, so an unchanged project saves
    /// to the same bytes it did before the camera existed.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tracks, forKey: .tracks)
        if camera != StoryboardCamera() { try container.encode(camera, forKey: .camera) }
    }

    // ─── Reading ─────────────────────────────────────────────────────────────

    /// Every placed effect, in draw order.
    ///
    /// Track order is draw order within a layer: the renderer sorts by layer
    /// and keeps array order to break ties, so a track later in this list draws
    /// in front of one before it.
    public var nodes: [EffectNode] {
        tracks.flatMap(\.nodes)
    }

    public subscript(id: EffectNode.ID) -> EffectNode? {
        get {
            for track in tracks {
                if let node = track.nodes.first(where: { $0.id == id }) { return node }
            }
            return nil
        }
        set {
            guard let location = locate(id) else { return }
            guard let newValue else {
                tracks[location.track].nodes.remove(at: location.node)
                return
            }
            tracks[location.track].nodes[location.node] = newValue
        }
    }

    public func track(id: EffectTrack.ID) -> EffectTrack? {
        tracks.first { $0.id == id }
    }

    /// Which track a node lives on.
    public func trackID(of nodeID: EffectNode.ID) -> EffectTrack.ID? {
        locate(nodeID).map { tracks[$0.track].id }
    }

    /// Whether a track is effectively editable — a locked one is not.
    public func isEditable(_ trackID: EffectTrack.ID) -> Bool {
        track(id: trackID).map { !$0.isLocked } ?? false
    }

    private func locate(_ nodeID: EffectNode.ID) -> (track: Int, node: Int)? {
        for (trackIndex, track) in tracks.enumerated() {
            if let nodeIndex = track.nodes.firstIndex(where: { $0.id == nodeID }) {
                return (trackIndex, nodeIndex)
            }
        }
        return nil
    }

    // ─── Tracks ──────────────────────────────────────────────────────────────

    /// Adds an empty track and returns it.
    ///
    /// Placed at the front of the draw order, which is the top of both lists.
    /// A new lane appearing behind everything else is a lane whose contents are
    /// hidden the moment anything is put on it.
    ///
    /// - Parameter index: where the lane lands in **document order**, or `nil`
    ///   to append. Asking from a row means asking for a lane *there* — a new
    ///   track that appears at the far end ignores the gesture that summoned
    ///   it, and leaves the author dragging it back to where they asked.
    @discardableResult
    public mutating func addTrack(
        named name: String? = nil,
        layer: Layer = .foreground,
        at index: Int? = nil,
    ) -> EffectTrack {
        let track = EffectTrack(
            id: "track-\(UUID().uuidString.prefix(8))",
            name: name ?? "Track \(tracks.count + 1)",
            layer: layer,
        )
        if let index {
            tracks.insert(track, at: min(max(0, index), tracks.count))
        } else {
            tracks.append(track)
        }
        return track
    }

    public mutating func removeTrack(_ trackID: EffectTrack.ID) {
        tracks.removeAll { $0.id == trackID }
    }

    public mutating func rename(_ trackID: EffectTrack.ID, to name: String) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // An empty name would leave a nameless row that cannot be clicked to
        // rename again, since there is nothing left to click.
        guard !trimmed.isEmpty else { return }
        tracks[index].name = trimmed
    }

    /// Renames one clip.
    ///
    /// `EffectNode.name` was written once, at placement — "Script", then
    /// "Script 2" — and never again, so a document with several scripts named
    /// them by the order they were dropped in. That is the one thing a name
    /// must not be: four clips called "Script 3" through "Script 6" carry no
    /// information about which one draws the wave.
    ///
    /// Same trimming and same empty guard as the track above, deliberately: a
    /// nameless block on a timeline cannot be identified, and the field that
    /// would fix it is reached by selecting that block.
    ///
    /// Named `renameNode` rather than overloading `rename`, because
    /// `EffectTrack.ID` and `EffectNode.ID` are **both `String`**: an overload
    /// would not just be ambiguous to a reader, it does not compile. This
    /// codebase already lost a test runner to two `prepare` functions that
    /// differed only by an argument label and resolved to each other.
    public mutating func renameNode(_ nodeID: EffectNode.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let location = locate(nodeID) else { return }
        tracks[location.track].nodes[location.node].name = trimmed
    }

    // ─── Filters ─────────────────────────────────────────────────────────────

    @discardableResult
    public mutating func addFilter(
        _ descriptor: FilterDescriptor,
        to nodeID: EffectNode.ID,
    ) -> FilterNode? {
        guard let location = locate(nodeID) else { return nil }

        let filter = FilterNode(
            id: "\(descriptor.type)-\(UUID().uuidString.prefix(8))",
            type: descriptor.type,
            values: descriptor.defaultValues,
        )
        tracks[location.track].nodes[location.node].filters.append(filter)
        return filter
    }

    public mutating func removeFilter(_ filterID: FilterNode.ID, from nodeID: EffectNode.ID) {
        guard let location = locate(nodeID) else { return }
        tracks[location.track].nodes[location.node].filters.removeAll { $0.id == filterID }
    }

    public mutating func setFilterValue(
        _ value: EffectValue,
        for parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        guard let location = locate(nodeID),
              let index = tracks[location.track].nodes[location.node].filters
                  .firstIndex(where: { $0.id == filterID })
        else { return }
        tracks[location.track].nodes[location.node].filters[index].values[parameterID] = value
    }

    /// Sets the keyframes driving one of a filter's parameters.
    ///
    /// Separate from ``setFilterValue(_:for:on:in:)`` rather than folded into
    /// it, which is the same split ``Transform`` draws between a resting value
    /// and its animation. Merged, moving the playhead and typing a number would
    /// plant keys nobody asked for.
    public mutating func setFilterAnimation(
        _ track: KeyframeTrack?,
        for parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        guard let location = locate(nodeID),
              let index = tracks[location.track].nodes[location.node].filters
                  .firstIndex(where: { $0.id == filterID })
        else { return }

        // Keys are clip-local, so one past the end names a moment the clip
        // never reaches: it would sit in the file, keep drawing in the lane,
        // and never be playable. Clamped here so every path in — dragging,
        // planting from the inspector, whatever comes next — obeys one limit.
        let duration = tracks[location.track].nodes[location.node].duration
        let clamped = track.map { existing in
            KeyframeTrack(
                existing.keyframes.map {
                    Keyframe(
                        id: $0.id,
                        time: min(max(0, $0.time), duration),
                        value: $0.value,
                        easing: $0.easing,
                    )
                },
                isEnabled: existing.isEnabled,
            )
        }

        if let clamped, !clamped.isEmpty {
            tracks[location.track].nodes[location.node]
                .filters[index].animations[parameterID] = clamped
        } else {
            tracks[location.track].nodes[location.node]
                .filters[index].animations[parameterID] = nil
        }
    }

    public mutating func toggleFilter(_ filterID: FilterNode.ID, in nodeID: EffectNode.ID) {
        guard let location = locate(nodeID),
              let index = tracks[location.track].nodes[location.node].filters
                  .firstIndex(where: { $0.id == filterID })
        else { return }
        tracks[location.track].nodes[location.node].filters[index].isEnabled.toggle()
    }

    /// Gives a track its own colour, or `nil` to follow its layer again.
    public mutating func setColour(_ colour: TrackColour?, on trackID: EffectTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].colour = colour
    }

    public mutating func setLayer(_ layer: Layer, on trackID: EffectTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].layer = layer
    }

    public mutating func toggleVisibility(of trackID: EffectTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].isVisible.toggle()
    }

    public mutating func toggleLock(of trackID: EffectTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].isLocked.toggle()
    }

    /// Moves a track one step later in the draw order, so it draws in front.
    ///
    /// Layer still wins — a Background track cannot be raised above a
    /// Foreground one, which is osu!'s rule rather than this editor's.
    public mutating func raiseTrack(_ trackID: EffectTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }),
              index < tracks.count - 1
        else { return }
        tracks.swapAt(index, index + 1)
    }

    public mutating func lowerTrack(_ trackID: EffectTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }), index > 0 else { return }
        tracks.swapAt(index, index - 1)
    }

    /// Moves a track to a position, in one operation.
    ///
    /// One move rather than a run of swaps. Sending a lane from the top of six
    /// to the bottom as five `lowerTrack` calls is five reorders of the same
    /// array — and every one of them is an edit the rest of the app answers,
    /// so the document is re-evaluated five times to reach one arrangement.
    ///
    /// - Parameter index: where the track should end up, in **document order**
    ///   (0 is the back of the stack). Clamped, so a caller can pass
    ///   `tracks.count` for "all the way up" without checking first.
    public mutating func moveTrack(_ trackID: EffectTrack.ID, toIndex index: Int) {
        guard let current = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let destination = min(max(0, index), tracks.count - 1)
        guard destination != current else { return }

        let track = tracks.remove(at: current)
        tracks.insert(track, at: destination)
    }

    public func canRaiseTrack(_ trackID: EffectTrack.ID) -> Bool {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return false }
        return index < tracks.count - 1
    }

    public func canLowerTrack(_ trackID: EffectTrack.ID) -> Bool {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return false }
        return index > 0
    }

    // ─── Effects ─────────────────────────────────────────────────────────────

    /// Adds an effect to a track, opening one when there is nowhere to put it.
    ///
    /// Tracks appear as they are needed rather than being created by hand:
    /// making an empty row before anything can go in it is friction in the way
    /// of the thing someone actually asked for.
    @discardableResult
    public mutating func add(
        _ descriptor: EffectDescriptor,
        at startTime: Double,
        duration: Double,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode {
        let index = trackIndex(preferring: trackID)

        let sameType = nodes.filter { $0.type == descriptor.type }.count
        let node = EffectNode(
            id: "\(descriptor.type)-\(UUID().uuidString.prefix(8))",
            type: descriptor.type,
            name: sameType == 0 ? descriptor.name : "\(descriptor.name) \(sameType + 1)",
            layer: tracks[index].layer,
            startTime: startTime,
            duration: duration,
            // Seeded from how many effects are already placed, so two emitters
            // dropped with the same settings do not come out as one field drawn
            // twice.
            seed: UInt64(nodes.count &+ 1) &* 0x9E37_79B9,
            values: descriptor.defaultValues,
            // Whatever the effect wants animated when it is first placed.
            //
            // Applied here rather than by whoever calls this, so every route in
            // gets it: an image placed from the library used to arrive with an
            // empty transform, no fade, and therefore a single zero-length
            // command — a sprite whose whole life lasted an instant.
            transform: descriptor.initialTransform(duration),
            // Whatever code the effect wants a fresh clip to start with.
            //
            // Applied here for the same reason as the transform above: every
            // route in gets it. A script clip built from `defaultValues` alone
            // would arrive empty and draw nothing, which reads as broken rather
            // than as waiting to be written.
            scriptSource: descriptor.initialSource,
        )
        tracks[index].nodes.append(node)
        return node
    }

    /// Where a new effect goes: the track asked for, the last one, or a fresh
    /// one when the document is empty.
    private mutating func trackIndex(preferring trackID: EffectTrack.ID?) -> Int {
        if let trackID, let index = tracks.firstIndex(where: { $0.id == trackID }) {
            return index
        }
        if tracks.isEmpty {
            addTrack(named: "Effects")
        }
        return tracks.count - 1
    }

    /// Copies an effect, placing the copy right after the original.
    ///
    /// Everything travels: parameters, keyframes, layer. Only the id and the
    /// seed are new — a duplicated emitter with the same seed would be the same
    /// field drawn twice, which is not what anyone means by "duplicate".
    @discardableResult
    public mutating func duplicate(_ nodeID: EffectNode.ID) -> EffectNode? {
        guard let location = locate(nodeID) else { return nil }
        let original = tracks[location.track].nodes[location.node]

        let copyID = "\(original.type)-\(UUID().uuidString.prefix(8))"
        let copySeed = original.seed &+ 0x9E37_79B9

        let copy = EffectNode(
            id: copyID,
            type: original.type,
            name: original.name,
            layer: original.layer,
            // Placed after the original rather than on top of it: two clips at
            // the same moment look like one, and the copy would be invisible.
            startTime: original.endTime,
            duration: original.duration,
            seed: copySeed,
            values: original.values,
            transform: original.transform,
            // Its filters too: a clip is what it does *and* how it looks, and a
            // copy that quietly drops the glow someone tuned is a copy of the
            // wrong thing.
            filters: original.filters.map { $0.reidentified() },
            // Its layers too, re-homed: a compound is one thing made of
            // several, and a copy missing them is a copy of the wrong thing.
            layers: original.layersRehomed(under: copyID, seed: copySeed),
            isVisible: original.isVisible,
            isLocked: original.isLocked,
            // Its code and declared controls too, for the same reason as its
            // filters: a copy of a script that drops the script is a copy of
            // nothing.
            scriptSource: original.scriptSource,
            // The reference, not a copy of the file: duplicating a clip shares
            // one source of truth, so editing it reloads both.
            scriptFile: original.scriptFile,
            scriptParameters: original.scriptParameters,
        )

        tracks[location.track].nodes.insert(copy, at: location.node + 1)
        return copy
    }

    /// Swaps a placed clip's preset, keeping what makes the clip itself.
    ///
    /// Only the preset's `overrides` land, so the author's text, font, colour
    /// and size survive — trying a second movement used to mean rebuilding the
    /// clip, which is the work presets exist to remove.
    ///
    /// Everything the **previous** preset set and this one does not name goes
    /// back to the effect's defaults rather than lingering. Left additive, a
    /// clip swapped twice would be a mixture of two movements and read as
    /// neither: the second preset is what was asked for, not the second on top
    /// of the first.
    ///
    /// A preset for another effect does nothing. Its keys would mean nothing
    /// here, and half-applying them is a clip nobody asked for.
    /// - Parameters:
    ///   - siblings: The other presets this effect ships, which is what says
    ///     which parameters a preset is allowed to own. Passing `[preset]`
    ///     alone is valid and simply clears less.
    public mutating func applyPreset(
        _ preset: EffectPreset,
        to nodeID: EffectNode.ID,
        siblings: [EffectPreset] = [],
        defaults: [String: EffectValue]? = nil,
    ) {
        guard let location = locate(nodeID) else { return }
        var node = tracks[location.track].nodes[location.node]
        guard node.type == preset.effectType else { return }

        // Cleared first: only the keys some preset of this effect can touch,
        // and only the ones this preset does not name.
        //
        // Not every default. That takes the author's text, font, colour and
        // size with it — measured: swapping put the text back to "HELLO" and
        // the size back to 48. And not nothing either, or a value the previous
        // preset set and this one omits would linger, leaving a clip that is a
        // mixture of two movements and reads as neither.
        //
        // The set is derived from the presets themselves rather than listed as
        // "animation" keys by hand. A hand-kept list is one to maintain, and
        // forgetting an entry there does not fail — it silently keeps
        // somebody's old movement, or silently discards their content.
        let animated = Set(siblings.flatMap(\.overrides.keys))
        for key in animated where preset.overrides[key] == nil {
            if let resting = defaults?[key] ?? preset.values[key] {
                node.values[key] = resting
            }
        }
        node.values.merge(preset.overrides) { _, new in new }

        tracks[location.track].nodes[location.node] = node
    }

    /// Changes one parameter on one effect.
    public mutating func setValue(_ value: EffectValue, for parameterID: String, on nodeID: EffectNode.ID) {
        guard let location = locate(nodeID) else { return }
        tracks[location.track].nodes[location.node].values[parameterID] = value
    }

    /// Sets a parameter on one layer of a compound effect.
    ///
    /// Addressed by the parent plus the layer's own id rather than by id alone:
    /// a layer is not in `tracks`, so `locate` cannot find it, and giving
    /// layers their own index would be a second place for the same truth.
    public mutating func setValue(
        _ value: EffectValue,
        for parameterID: String,
        onLayer layerID: EffectNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        guard let location = locate(nodeID) else { return }
        guard let index = tracks[location.track].nodes[location.node]
            .layers.firstIndex(where: { $0.id == layerID }) else { return }
        tracks[location.track].nodes[location.node].layers[index].values[parameterID] = value
    }

    /// Shows or hides one layer of a compound effect.
    ///
    /// Worth having on its own: a compound is several things at once, and the
    /// fastest way to learn what each contributes is to switch one off.
    public mutating func toggleLayerVisibility(_ layerID: EffectNode.ID, in nodeID: EffectNode.ID) {
        guard let location = locate(nodeID) else { return }
        guard let index = tracks[location.track].nodes[location.node]
            .layers.firstIndex(where: { $0.id == layerID }) else { return }
        tracks[location.track].nodes[location.node].layers[index].isVisible.toggle()
    }

    // ─── Keyframes ───────────────────────────────────────────────────────────

    /// Sets a keyframe on one property of one effect.
    ///
    /// - Parameter time: local to the clip, so moving the clip moves its
    ///   animation with it.
    public mutating func setKeyframe(
        _ value: Double,
        for property: TransformProperty,
        at time: Double,
        easing: Easing = .linear,
        on nodeID: EffectNode.ID,
    ) {
        guard let location = locate(nodeID) else { return }
        let node = tracks[location.track].nodes[location.node]
        var track = node.transform[property]
        // Adding a key to a switched-off track switches it back on: putting one
        // down is a request to animate, and leaving it inert would look like
        // the click did nothing.
        track.isEnabled = true
        // Both ends, not just the floor: a key past the clip's end is one the
        // clip never reaches.
        track.set(value, at: min(max(0, time), node.duration), easing: easing)
        tracks[location.track].nodes[location.node].transform[property] = track
    }

    /// Sets a property's resting value, without touching its animation.
    public mutating func setTransformValue(
        _ value: Double,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        guard let location = locate(nodeID) else { return }
        tracks[location.track].nodes[location.node].transform[value: property] = value
    }

    public mutating func removeKeyframe(
        _ keyframeID: Keyframe.ID,
        from property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        guard let location = locate(nodeID) else { return }
        var track = tracks[location.track].nodes[location.node].transform[property]
        track.remove(keyframeID)
        tracks[location.track].nodes[location.node].transform[property] = track
    }

    public mutating func moveKeyframe(
        _ keyframeID: Keyframe.ID,
        in property: TransformProperty,
        to time: Double,
        on nodeID: EffectNode.ID,
    ) {
        guard let location = locate(nodeID) else { return }
        let node = tracks[location.track].nodes[location.node]

        // Held inside the clip.
        //
        // Keyframe times are local to the clip, so one dragged past its end is
        // a moment the clip never reaches — the key is still in the file, still
        // shown in the row, and can never be played. Clamped here rather than
        // in the row that drags it, so every route in obeys the same bound.
        let bounded = min(max(0, time), node.duration)

        var track = node.transform[property]
        track.move(keyframeID, to: bounded)
        tracks[location.track].nodes[location.node].transform[property] = track
    }

    public mutating func setKeyframeEasing(
        _ easing: Easing,
        for keyframeID: Keyframe.ID,
        in property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        guard let location = locate(nodeID) else { return }
        var track = tracks[location.track].nodes[location.node].transform[property]
        track.setEasing(easing, for: keyframeID)
        tracks[location.track].nodes[location.node].transform[property] = track
    }

    /// Switches a property's animation on or off, keeping its keys.
    ///
    /// The keys survive: one click should not destroy a stopwatch's worth of
    /// work, least of all the same click that started it.
    public mutating func setAnimationEnabled(
        _ isEnabled: Bool,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        keeping time: Double = 0,
    ) {
        guard let location = locate(nodeID) else { return }
        var transform = tracks[location.track].nodes[location.node].transform

        // Turning it off leaves the property where the animation had it, so the
        // sprite does not jump when the switch is flipped.
        if !isEnabled, transform[property].isActive {
            transform[value: property] = transform.value(property, at: time)
        }

        var track = transform[property]
        track.isEnabled = isEnabled
        transform[property] = track
        tracks[location.track].nodes[location.node].transform = transform
    }

    /// Stops animating a property, keeping what it was worth at `time`.
    ///
    /// The value is kept rather than reset: switching animation off is a
    /// decision about *how* a property behaves, not about what it is, and
    /// snapping the sprite back to a system default would be a second,
    /// unasked-for change.
    public mutating func clearKeyframes(
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        keeping time: Double = 0,
    ) {
        guard let location = locate(nodeID) else { return }
        let held = tracks[location.track].nodes[location.node].transform.value(property, at: time)
        tracks[location.track].nodes[location.node].transform[property] = KeyframeTrack()
        tracks[location.track].nodes[location.node].transform[value: property] = held
    }

    /// Replaces a node's whole transform, for placing something preconfigured.
    public mutating func setTransform(_ transform: Transform, on nodeID: EffectNode.ID) {
        guard let location = locate(nodeID) else { return }
        tracks[location.track].nodes[location.node].transform = transform
    }

    /// Moves an effect along its track without changing how long it runs.
    ///
    /// Clamped at zero: a storyboard can open before the audio does, but a
    /// negative start would be dragged past the left edge of the timeline with
    /// no way to grab it back.
    public mutating func move(_ nodeID: EffectNode.ID, to startTime: Double) {
        guard let location = locate(nodeID) else { return }
        tracks[location.track].nodes[location.node].startTime = max(0, startTime)
    }

    /// Moves an effect to another track, keeping its position in time.
    ///
    /// The effect takes on the destination's layer: the layer is a property of
    /// the lane, and a node carrying its old one would draw in a place its row
    /// does not claim.
    public mutating func move(_ nodeID: EffectNode.ID, toTrack trackID: EffectTrack.ID) {
        guard let from = locate(nodeID),
              let to = tracks.firstIndex(where: { $0.id == trackID }),
              from.track != to
        else { return }

        var node = tracks[from.track].nodes.remove(at: from.node)
        node.layer = tracks[to].layer
        tracks[to].nodes.append(node)
    }

    /// Resizes an effect from one edge, keeping the other where it is.
    /// Resizes an effect from one edge, keeping the other where it is.
    ///
    /// The animation stretches with the clip. Left where they were, the keys
    /// would describe a moment that is now a fraction of the way in — stretch a
    /// four-second clip to twenty-six and its fade-out lands at second four,
    /// leaving twenty-two seconds of an invisible sprite.
    public mutating func resize(
        _ nodeID: EffectNode.ID,
        startTime: Double,
        duration: Double,
        minimumDuration: Double = 100,
    ) {
        guard let location = locate(nodeID) else { return }
        // A sound is as long as its file; no entry point stretches it.
        guard tracks[location.track].nodes[location.node].type != SampleEffect.descriptor.type else { return }
        let old = tracks[location.track].nodes[location.node].duration
        let new = max(minimumDuration, duration)
        let oldStart = tracks[location.track].nodes[location.node].startTime

        tracks[location.track].nodes[location.node].startTime = max(0, startTime)
        // Sung words stay on the song: trimming the start moves the clip's
        // zero, not the moment each word was sung. Unlike keyframes, which are
        // the author's and stretch with the clip, these belong to the audio.
        let shift = oldStart - max(0, startTime)
        if shift != 0, let sung = tracks[location.track].nodes[location.node].sungWords {
            tracks[location.track].nodes[location.node].sungWords = sung.map {
                SungWord(start: $0.start + shift, end: $0.end + shift, characters: $0.characters)
            }
        }
        tracks[location.track].nodes[location.node].duration = new
        tracks[location.track].nodes[location.node].transform.rescale(from: old, to: new)
    }

    public mutating func remove(_ nodeID: EffectNode.ID) {
        self[nodeID] = nil
    }

    /// The span every placed effect covers, or `nil` when nothing is placed.
    ///
    /// - Parameter playedDuration: how long a clip of a given length actually
    ///   runs on a track, once its filters are applied. A looped clip plays
    ///   past its own block, and a timeline that stopped at the block would cut
    ///   the repeats off screen.
    public func timeRange(
        playedDuration: (EffectTrack.ID, Double) -> Double = { _, duration in duration },
    ) -> ClosedRange<Double>? {
        var lower: Double?
        var upper: Double?

        for track in tracks {
            for node in track.nodes {
                lower = min(lower ?? node.startTime, node.startTime)
                let end = node.startTime + playedDuration(track.id, node.duration)
                upper = max(upper ?? end, end)
            }
        }

        guard let lower, let upper else { return nil }
        return lower...max(lower, upper)
    }

    /// The span every placed effect covers, ignoring what filters add.
    public var timeRange: ClosedRange<Double>? {
        timeRange()
    }
}
