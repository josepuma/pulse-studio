import CoreGraphics
import Foundation
import StoryboardCore

/// Which panel the left rail is showing.
public enum SidePanel: String, CaseIterable, Identifiable, Sendable {
    case assets
    /// The effect library. Its own case since scripts got a tab of their own:
    /// this used to be `.scripts` — a name left from when the panel was the
    /// script browser — so the rail's `{}` opened "Effects".
    case effects
    case filters
    case scripts
    case layers
    case lyrics

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .assets: "photo.stack"
        case .effects: "sparkles"
        case .scripts: "curlybraces"
        case .filters: "wand.and.stars"
        case .layers: "square.3.layers.3d"
        case .lyrics: "text.bubble"
        }
    }

    public var title: String {
        switch self {
        case .assets: "Assets"
        case .effects: "Effects"
        case .scripts: "Scripts"
        case .filters: "Filters"
        case .layers: "Layers"
        case .lyrics: "Lyrics"
        }
    }
}

/// An image the storyboard references.
/// Where an imported file is copied to.
///
/// osu! reads the two places differently, and a file in the wrong one is broken
/// in a way nothing shows until export: the root is the **beatmap's** own art —
/// the background, the video — and `sb/` is the **storyboard's**. Asking is
/// cheaper than importing wrong and untangling it later, which is exactly what
/// happened when the button chose for you.
public enum AssetDestination: String, CaseIterable, Identifiable, Sendable {
    /// The beatmap folder itself: backgrounds and video.
    case root
    /// `sb/`, where a storyboard's images live by convention.
    case storyboard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .root: "Beatmap Root"
        case .storyboard: "Storyboard (sb/)"
        }
    }

    public var detail: String {
        switch self {
        case .root: "Backgrounds and video — what the map itself uses."
        case .storyboard: "Images the storyboard draws."
        }
    }

    /// The subfolder to copy into, relative to the beatmap folder.
    public var relativeFolder: String {
        switch self {
        case .root: ""
        case .storyboard: "sb"
        }
    }
}

public struct AssetItem: Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case all
        case image
        case audio

        public var id: String { rawValue }

        /// Sounds the game plays as samples, and the images it draws.
        public static let audioExtensions: Set<String> = ["wav", "mp3", "ogg"]
        public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg"]

        /// What a file is, from its extension — case-insensitive, because a
        /// mapper's `Hit.WAV` is as much a sound as `hit.wav`.
        public static func inferred(from path: String) -> Kind {
            let ext = (path as NSString).pathExtension.lowercased()
            return audioExtensions.contains(ext) ? .audio : .image
        }

        /// Whether the panel can hold the file at all.
        public static func isSupported(_ path: String) -> Bool {
            let ext = (path as NSString).pathExtension.lowercased()
            return audioExtensions.contains(ext) || imageExtensions.contains(ext)
        }

        public var title: String {
            switch self {
            case .all: "All"
            case .image: "Images"
            case .audio: "Audio"
            }
        }
    }

    public let id: String
    public var name: String
    public var path: String

    /// Which folder the file sits in, for the panel to show.
    ///
    /// The panel used to keep only the last component, so `bg.jpg` at the root
    /// and `sb/bg.jpg` looked identical — and a background imported into the
    /// wrong place was invisible until export time, when it is a nuisance to
    /// untangle. Where a file lives is part of what it *is* here: osu! reads
    /// the root for the map's own art and `sb/` for the storyboard's.
    public var folder: String {
        let directory = (path as NSString).deletingLastPathComponent
        return directory.isEmpty ? "root" : directory
    }

    public var kind: Kind
    /// How many sprites reference this file.
    public var useCount: Int
    public var isMissing: Bool

    public init(
        id: String,
        name: String,
        path: String,
        kind: Kind,
        useCount: Int,
        isMissing: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.useCount = useCount
        self.isMissing = isMissing
    }
}

/// State for the editor shell: which panels are open and what they show.
@MainActor
@Observable
public final class EditorShellModel {
    public var sidePanel: SidePanel = .layers
    public var isSidePanelVisible = true
    public var isInspectorVisible = true
    /// Which of a clip's tabs the inspector shows.
    ///
    /// On the model rather than in the panel's `@State`: the inspector is
    /// rebuilt whenever the selection changes, and a tab that snapped back to
    /// the first every time a different clip was picked would make comparing
    /// two clips' filters two clicks per glance. Kept across clips, the way
    /// After Effects keeps its panel where you left it.
    public var inspectorTab: InspectorTab = .effect
    public var assetFilter: AssetItem.Kind = .all

    public private(set) var assets: [AssetItem] = []

    /// The lane the next effect lands on, and what the inspector shows when no
    /// effect is selected.
    public var selectedTrackID: EffectTrack.ID?
    /// The effect being edited — the one the inspector shows.
    ///
    /// With several clips selected this is the one picked last, and the rest
    /// are in `selectedNodeIDs`. Assigning it directly selects just that clip:
    /// every place that selects one thing — a click, a paste, an arrow key —
    /// keeps meaning what it meant, and none of them can leave a stale group
    /// behind.
    public var selectedNodeID: EffectNode.ID? {
        didSet {
            if !isAdjustingGroup {
                setGroup(selectedNodeID.map { [$0] } ?? [])
            }
            guard selectedNodeID != oldValue else { return }
            revealScriptEditorIfNeeded()
        }
    }

    /// Every selected clip, `selectedNodeID` included.
    ///
    /// A set beside the single id rather than replacing it: the inspector, the
    /// keyframe editor and a dozen menus describe *one* clip, and a group is
    /// what moves, deletes and duplicates together.
    public private(set) var selectedNodeIDs: Set<EffectNode.ID> = [] {
        didSet {
            guard selectedNodeIDs != oldValue else { return }
            onSelectionChanged?(selectedNodeIDs)
        }
    }

    /// Set while the group is being edited, so assigning the inspected clip
    /// does not collapse the group back to one.
    @ObservationIgnored private var isAdjustingGroup = false

    /// Written only when it changes: an `@Observable` setter notifies even for
    /// the same value, and every view reading the selection would rebuild on
    /// every click.
    private func setGroup(_ group: Set<EffectNode.ID>) {
        guard selectedNodeIDs != group else { return }
        selectedNodeIDs = group
    }

    /// Replaces the group, keeping the inspected clip if it is still in it.
    private func select(group: Set<EffectNode.ID>) {
        isAdjustingGroup = true
        defer { isAdjustingGroup = false }
        setGroup(group)
        if let selectedNodeID, group.contains(selectedNodeID) { return }
        // In document order rather than the set's: a set has none, and the
        // inspector jumping to a different clip for the same group would read
        // as random.
        selectedNodeID = effects.nodes.first { group.contains($0.id) }?.id
    }

    /// ⌘- or ⇧-click: adds a clip to the selection, or takes it out.
    ///
    /// An added clip becomes the inspected one — it is what the hand just
    /// pointed at.
    public func toggleNodeSelection(_ nodeID: EffectNode.ID) {
        var group = selectedNodeIDs
        if group.contains(nodeID) {
            group.remove(nodeID)
            select(group: group)
        } else {
            group.insert(nodeID)
            isAdjustingGroup = true
            setGroup(group)
            selectedNodeID = nodeID
            isAdjustingGroup = false
        }
    }

    /// ⌘A: every clip on every lane.
    public func selectAllClips() {
        select(group: Set(effects.nodes.map(\.id)))
    }

    /// The selected clips a drag can move — the group less its locked clips.
    ///
    /// What the canvas previews a drag on, so a locked clip in a group stays
    /// drawn where it is, as the commit will leave it.
    public var movableSelectionIDs: Set<EffectNode.ID> {
        selectedNodeIDs.filter { !isLocked($0) }
    }

    /// The clips a click on the canvas may pick: every one not on a locked
    /// lane.
    ///
    /// A locked lane is clicked through, the way a locked layer is in any
    /// editor — it is what keeps a full-screen background from catching every
    /// click meant for what is drawn over it. A hidden clip draws nothing, so
    /// it is never under the pointer to begin with.
    public var canvasPickableClipIDs: Set<EffectNode.ID> {
        var ids: Set<EffectNode.ID> = []
        for track in effects.tracks where !track.isLocked {
            for node in track.nodes { ids.insert(node.id) }
        }
        return ids
    }

    /// A click on the canvas: selects what it landed on, or with ⌘/⇧ adds it
    /// to the selection.
    ///
    /// A plain click on nothing clears the selection, as clicking empty canvas
    /// always has. An added click on nothing does not: it is a slip on the way
    /// to building a group, not a request to drop it.
    public func pickOnCanvas(_ nodeID: EffectNode.ID?, adding: Bool) {
        guard let nodeID else {
            guard !adding else { return }
            selectedNodeID = nil
            selectedKeyframe = nil
            return
        }
        if adding {
            toggleNodeSelection(nodeID)
        } else if !(selectedNodeIDs.count == 1 && selectedNodeID == nodeID) {
            selectedNodeID = nodeID
        }
    }

    /// Drops clips that no longer exist from the selection.
    private func pruneSelection() {
        select(group: selectedNodeIDs.filter { effects[$0] != nil })
    }

    /// The selected clips in document order, which is the order a batch edit
    /// walks them in so its result never depends on a set's.
    private var selectedNodesInOrder: [EffectNode] {
        effects.nodes.filter { selectedNodeIDs.contains($0.id) }
    }

    /// Shows the script panel when a script clip is selected.
    ///
    /// In `selectedNodeID`'s `didSet` rather than at the places that select,
    /// because there are several — a click on the timeline, a click on the
    /// canvas, a paste, an arrow key — and an editor that appears for some of
    /// them is worse than one that never does: you learn it is unreliable
    /// rather than learning where it is.
    ///
    /// Selecting the clip is the whole gesture. The editor existed before this
    /// and was reachable only by then switching panels by hand, which means the
    /// feature was hidden behind knowing it was there.
    ///
    /// It does not switch **away** on deselecting, or on selecting something
    /// else. Taking a panel back is a second decision the author did not ask
    /// for, and a rail that moves under you twice per click is worse than one
    /// that moves once.
    private func revealScriptEditorIfNeeded() {
        guard let nodeID = selectedNodeID,
              effects[nodeID]?.type == ScriptEffect.descriptor.type
        else { return }

        sidePanel = .scripts
        isSidePanelVisible = true

        // The inspector is left exactly as it was.
        //
        // It used to be closed once, on the way in, to make room — and a panel
        // closing by itself is a decision the author did not ask for. Worse,
        // the one thing it hid is a script's own `params`: controls that exist
        // and cannot be seen. Whoever needs the width can take it from the
        // toggle that is already there.
    }

    /// Told the moment the selection changes.
    ///
    /// A callback rather than something the app reads in a `body`: reading it
    /// there subscribes the window to it, and going through `.task(id:)`
    /// instead put a scheduling hop between the click and the canvas — the
    /// frame that draws the selection box could not run until that hop landed.
    @ObservationIgnored public var onSelectionChanged: ((Set<EffectNode.ID>) -> Void)?

    /// Moves the playhead, for controls that navigate between keyframes.
    ///
    /// A seam like `exportHandler`: the clock lives in the playback feature and
    /// features do not import each other, so the app connects the two. Optional
    /// so the shell runs without it — the arrows simply do nothing, which is
    /// better than a shell that cannot be built.
    ///
    /// Takes **song** time, since that is what a seek means everywhere else;
    /// callers holding a clip-local keyframe time add the clip's start.
    @ObservationIgnored public var seekHandler: ((Double) -> Void)?

    /// The keyframe being edited, if any.
    ///
    /// Selected rather than only draggable: a key's easing and its exact time
    /// are worth editing in a field, and a field needs to know which key it is
    /// talking about.
    public struct KeyframeSelection: Equatable, Sendable {
        public let nodeID: EffectNode.ID
        public let property: TransformProperty
        public let keyframeID: Keyframe.ID
    }

    public var selectedKeyframe: KeyframeSelection? {
        didSet {
            if selectedKeyframe != nil {
                selectedFilterKeyframe = nil
                selectedCameraKeyframe = nil
            }
        }
    }

    /// A selected key on the storyboard camera.
    ///
    /// Its own shape because the camera belongs to no clip: it names a
    /// `CameraProperty`, and its keys are in song time.
    public struct CameraKeyframeSelection: Equatable, Sendable {
        public let property: CameraProperty
        public let keyframeID: Keyframe.ID

        public init(property: CameraProperty, keyframeID: Keyframe.ID) {
            self.property = property
            self.keyframeID = keyframeID
        }
    }

    /// One selection with three shapes: picking any releases the others, so
    /// the inspector never describes one key while another sits highlighted.
    public var selectedCameraKeyframe: CameraKeyframeSelection? {
        didSet {
            if selectedCameraKeyframe != nil {
                selectedKeyframe = nil
                selectedFilterKeyframe = nil
            }
        }
    }

    /// The selected camera key itself, when there is one.
    public var selectedCameraKeyframeValue: Keyframe? {
        guard let selection = selectedCameraKeyframe else { return nil }
        return camera[selection.property].keyframes.first { $0.id == selection.keyframeID }
    }

    /// Whether the timeline is showing the camera's keys.
    ///
    /// A mode like a clip's keyframe editor, and exclusive with it: both own
    /// the whole timeline. The camera's keys are in song time, so the ruler
    /// keeps spanning the song rather than narrowing to one clip.
    public var isEditingCamera = false {
        didSet {
            guard isEditingCamera != oldValue else { return }
            if isEditingCamera {
                keyframeNodeID = nil
            } else {
                selectedCameraKeyframe = nil
                // The view belongs to the mode: coming back later starts on
                // the world, which is what the mode is for.
                isViewingThroughCamera = false
            }
            // The canvas switches between the world and the finished picture.
            // Nothing in the document changed, so no clip re-runs and nothing
            // is marked unsaved — the pass re-reads the cache.
            if !hasPendingClipEdit { onlyCameraMoved = true }
            reevaluate()
        }
    }

    /// A selected key on one of a clip's filters.
    ///
    /// Separate from ``KeyframeSelection`` rather than folded into it: that one
    /// names a `TransformProperty`, and a filter's parameters are strings that
    /// belong to a particular filter node. Widening the existing type would
    /// make every reader handle a case it does not care about.
    public struct FilterKeyframeSelection: Equatable, Sendable {
        public let nodeID: EffectNode.ID
        public let filterID: FilterNode.ID
        public let parameter: String
        public let keyframeID: Keyframe.ID
    }

    public var selectedFilterKeyframe: FilterKeyframeSelection? {
        // The two are one selection wearing two shapes, so picking either has
        // to release the other — otherwise the inspector would show a
        // transform key while a filter's diamond sits highlighted.
        didSet {
            if selectedFilterKeyframe != nil {
                selectedKeyframe = nil
                selectedCameraKeyframe = nil
            }
        }
    }

    /// The selected key itself, when there is one.
    public var selectedKeyframeValue: Keyframe? {
        guard let selection = selectedKeyframe,
              let node = effects[selection.nodeID]
        else { return nil }
        return node.transform[selection.property].keyframes
            .first { $0.id == selection.keyframeID }
    }

    /// The selected filter key itself, when there is one.
    public var selectedFilterKeyframeValue: Keyframe? {
        guard let selection = selectedFilterKeyframe else { return nil }
        return filterAnimation(
            selection.parameter, on: selection.filterID, in: selection.nodeID,
        )?.keyframes.first { $0.id == selection.keyframeID }
    }

    /// Selects the key at a moment on a transform property, if there is one.
    ///
    /// Jumping to a key and not selecting it leaves the inspector describing
    /// something else — the arrow moved the playhead onto a key that the panel
    /// then declines to talk about.
    public func selectKeyframe(
        at localTime: Double,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        guard let node = effects[nodeID],
              let key = node.transform[property].keyframes
                  .first(where: { abs($0.time - localTime) < 1 })
        else { return }
        selectedKeyframe = KeyframeSelection(
            nodeID: nodeID, property: property, keyframeID: key.id,
        )
    }

    /// Selects the key at a moment on a filter parameter, if there is one.
    public func selectFilterKeyframe(
        at localTime: Double,
        for parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        guard let key = filterAnimation(parameterID, on: filterID, in: nodeID)?
            .keyframes.first(where: { abs($0.time - localTime) < 1 })
        else { return }
        selectedFilterKeyframe = FilterKeyframeSelection(
            nodeID: nodeID, filterID: filterID,
            parameter: parameterID, keyframeID: key.id,
        )
    }

    /// The clip whose keyframes the timeline is showing, if any.
    ///
    /// A mode rather than rows stacked under every lane: five properties per
    /// clip is unreadable by the second clip, and the keys are worth the whole
    /// timeline's width when you are actually working on them. Double-clicking
    /// a clip is how a video editor opens something for detailed work.
    public var keyframeNodeID: EffectNode.ID? {
        didSet {
            // A selection belongs to the clip being edited: leaving that clip
            // would otherwise leave the inspector showing a key from a row that
            // is no longer on screen.
            if keyframeNodeID != oldValue { selectedKeyframe = nil }
            if keyframeNodeID != nil { isEditingCamera = false }
        }
    }

    /// The clip the keyframe editor is open on.
    public var keyframeNode: EffectNode? {
        guard let keyframeNodeID else { return nil }
        return effects[keyframeNodeID]
    }

    /// The last evaluation, kept so the sprites are produced once per change
    /// rather than once per reader.
    private var evaluated: [StoryboardSprite] = []

    /// Where a clip being dragged would land, while the drag is in flight.
    ///
    /// Held here rather than in the row doing the dragging because the preview
    /// belongs to a *different* row — the destination — and a row cannot draw
    /// into its neighbour.
    public struct DropPreview: Equatable, Sendable {
        public let nodeID: EffectNode.ID
        public let trackID: EffectTrack.ID
        public let range: ClosedRange<Double>
    }

    public var dropPreview: DropPreview?

    /// The time a dragged clip has snapped to, while the drag is in flight.
    ///
    /// Held here for the same reason as `dropPreview`: the line runs through
    /// every lane, and the row doing the dragging can only draw in itself.
    public var timelineSnapGuide: Double?

    /// How far a selected group has been dragged along the timeline, while the
    /// drag is in flight.
    ///
    /// In the model because the group spans lanes, and only the row holding
    /// the grabbed clip sees the gesture: every other row reads this to draw
    /// its selected clips where the hand has taken them.
    public var timelineGroupShift: Double?

    /// What a clip dragged along the timeline can line up with, besides the
    /// beat: every other clip's two edges, on any lane, and the playhead.
    ///
    /// Lanes are separate on screen, not in time — a clip on another lane is
    /// exactly what a hit on this one lines up against. The dragged clip is
    /// left out, or it would stick to wherever it started.
    public func timelineSnapAnchors(excluding nodeID: EffectNode.ID) -> [Double] {
        var anchors = [playheadTime]
        for node in effects.nodes where node.id != nodeID {
            anchors.append(node.startTime)
            anchors.append(node.startTime + node.duration)
        }
        return anchors
    }

    public var visibleAssets: [AssetItem] {
        let listed = assetFilter == .all ? assets : assets.filter { $0.kind == assetFilter }
        // A sound is used by the sample clips that name it, not by sprites, so
        // its count comes from the document at read time. Cached at load it
        // would go stale with every sample placed or deleted.
        guard listed.contains(where: { $0.kind == .audio }) else { return listed }
        var uses: [String: Int] = [:]
        for node in effects.nodes where node.type == SampleEffect.descriptor.type {
            if case let .text(path)? = node.values[SampleEffect.Param.file] {
                uses[path, default: 0] += 1
            }
        }
        return listed.map { asset in
            guard asset.kind == .audio else { return asset }
            var copy = asset
            copy.useCount = uses[asset.path] ?? 0
            return copy
        }
    }

    /// The effects placed on the timeline — what the project actually authors,
    /// as opposed to the layer tracks derived from a parsed `.osb`.
    public private(set) var effects = EffectDocument() {
        // Captured here rather than at each of the thirty-odd mutations.
        //
        // A `willSet` sees both sides of every write, whoever made it, so undo
        // cannot be forgotten when an edit is added later — and a gap in an
        // undo stack is worse than no undo at all: it takes the document
        // somewhere the author never was.
        willSet {
            guard isRecordingUndo else { return }
            // One entry per gesture, not per step.
            //
            // A slider dragged across its range writes on every step, and each
            // write copies the whole document — measured at 300KB for a busy
            // project, that is megabytes a second of copying on the main
            // thread, and it is what made a drag stutter as it went.
            //
            // It is also what every editor does: undoing a drag returns to
            // where the drag started, not one pixel back. Fifty undo steps to
            // escape one gesture is a stack nobody can use.
            guard !isCoalescingUndo else { return }
            history.record(effects)
        }
        didSet { publishSamples() }
    }

    // ─── Samples in the preview ──────────────────────────────────────────────

    /// Told the document's samples whenever the list changes.
    ///
    /// Sent only when it differs from what was last sent: `effects` is written
    /// on every drag step, and the preview's schedule has no use for the same
    /// list sixty times a second. Installing the callback sends the current
    /// list, so wiring it after a project opened still catches up.
    @ObservationIgnored public var onSamplesChanged: (([StoryboardSample]) -> Void)? {
        didSet {
            sentSamples = nil
            publishSamples()
        }
    }

    @ObservationIgnored private var sentSamples: [StoryboardSample]?

    private func publishSamples() {
        guard let onSamplesChanged else { return }
        let samples = effects.samples
        guard samples != sentSamples else { return }
        sentSamples = samples
        onSamplesChanged(samples)
    }

    /// Sample files the preview is silent for, with why. Set by the app from
    /// the player; the export still ships them.
    public var unplayableSamplePaths: [String: SamplePreviewIssue] = [:]

    /// Why a sample clip's file cannot be previewed; `nil` when it can.
    public func cannotPreview(_ node: EffectNode) -> SamplePreviewIssue? {
        guard node.type == SampleEffect.descriptor.type,
              case let .text(path)? = node.values[SampleEffect.Param.file]
        else { return nil }
        return unplayableSamplePaths[path]
    }

    /// Whether edits are being folded into one undo entry.
    @ObservationIgnored private var isCoalescingUndo = false

    /// Folds every edit until ``endGesture()`` into a single undo step.
    ///
    /// Called when a continuous gesture starts — a slider grabbed, a field
    /// focused, a clip picked up. The first write still records, so the entry
    /// holds the document as it was *before* the gesture.
    public func beginGesture() {
        guard !isCoalescingUndo else { return }
        history.record(effects)
        isCoalescingUndo = true
        isGestureActive = true
    }

    /// Ends a coalesced gesture, so the next edit records again.
    public func endGesture() {
        isCoalescingUndo = false
        isGestureActive = false
        // Straight away on release: the pause is for while a hand is moving,
        // and waiting after it stops is a delay nobody asked for.
        pendingEvaluation?.cancel()
        evaluateNow()
    }

    /// Turned off while undo itself is writing, so stepping back does not
    /// record the step back as an edit — the stack would fill with itself and
    /// a second undo would go nowhere.
    @ObservationIgnored private var isRecordingUndo = true

    /// Undo and redo.
    ///
    /// Not observed: the history changes on every edit and nothing about the
    /// view depends on its contents — only on whether the two commands are
    /// available, which is read at menu time.
    @ObservationIgnored private var history = EditHistory()

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    public func undo() {
        guard let previous = history.undo(from: effects) else { return }
        withoutRecording { effects = previous }
        effectsChanged()
    }

    public func redo() {
        guard let next = history.redo(from: effects) else { return }
        withoutRecording { effects = next }
        effectsChanged()
    }

    private func withoutRecording(_ write: () -> Void) {
        isRecordingUndo = false
        write()
        isRecordingUndo = true
    }
    public let library: EffectLibrary
    public let filters: FilterLibrary
    // A `var` because the beat is set after the map opens: tempo comes off
    // the beatmap, and this feature never opens one.
    private var evaluator: EffectEvaluator

    /// Bumped whenever an effect changes, so views that re-evaluate can watch
    /// one value instead of diffing the whole document.
    public private(set) var effectsRevision = 0

    /// What reads the open song, for the effects that listen to it.
    ///
    /// Set when a project opens rather than at construction: the track is
    /// only known then. Nothing is re-evaluated here — the app already calls
    /// `inputsChanged()` once the audio has loaded, which is the moment the
    /// answer changes.
    public var audioAnalyser: AudioSpectrum.Analyser? {
        didSet { evaluator.audio = audioAnalyser }
    }

    /// - Parameter scriptRuntime: what runs script clips. The app passes the
    ///   JavaScript engine; `nil` leaves script clips drawing nothing, which is
    ///   what a shell built in a test without one should do.
    public init(
        library: EffectLibrary = .standard,
        filters: FilterLibrary = .standard,
        scriptRuntime: ScriptRuntime.Runner? = nil,
    ) {
        self.library = library
        self.filters = filters
        evaluator = EffectEvaluator(library: library, filters: filters, scriptRuntime: scriptRuntime)
    }

    // ─── Effects ─────────────────────────────────────────────────────────────

    /// The effect the inspector edits.
    ///
    /// Falls back to the only effect on the selected lane. Clicking a row with
    /// one clip on it and getting an empty inspector is the wrong answer to an
    /// obvious question — there is exactly one thing there to edit. With
    /// several, the lane itself is the selection and the inspector shows what a
    /// lane has.
    public var selectedEffect: EffectNode? {
        if let selectedNodeID, let node = effects[selectedNodeID] { return node }

        // In keyframe mode, the clip being edited *is* the selection.
        //
        // The mode opens on one clip and fills the timeline with its
        // properties, so there is nothing ambiguous about which one the panel
        // should describe — and the rows on screen name it. Without this the
        // inspector fell back to the lane and showed a track's name and layer
        // while the timeline underneath was plainly editing a clip's Glow: two
        // halves of the window disagreeing about what is selected.
        //
        // This is not the "lane's only effect" shortcut removed below. That one
        // guessed at a clip nothing had chosen; this one names the clip the mode
        // was opened on.
        if let keyframeNodeID, let node = effects[keyframeNodeID] { return node }

        // No clip selected means no clip's parameters.
        //
        // A lane's only effect used to answer here, so a row holding one clip
        // did not need that clip clicked as well. Convenient, and it meant the
        // panel never emptied: after deselecting, it went on offering
        // parameters for something nothing on screen said was chosen. A panel
        // that describes an unselected clip is editing blind, and picking the
        // clip is one click.
        return nil
    }

    /// The descriptor behind the selected effect, for the inspector to render.
    public var selectedDescriptor: EffectDescriptor? {
        guard let node = selectedEffect else { return nil }
        // From the node: an effect that declares its controls from stored state
        // answers per node, and resolving by type would show one clip's
        // parameters while another is selected.
        return library.descriptor(for: node)
    }

    /// The track the selection belongs to, or the selected track itself.
    public var selectedTrack: EffectTrack? {
        if let selectedNodeID, let id = effects.trackID(of: selectedNodeID) {
            return effects.track(id: id)
        }
        guard let selectedTrackID else { return nil }
        return effects.track(id: selectedTrackID)
    }

    /// Every placed effect evaluated into sprites.
    ///
    /// The last completed pass. A caller that needs the sprites for the
    /// *document as it stands right now* — an export, a test — awaits
    /// ``awaitEvaluation()`` first; one that wants something to draw takes what
    /// is here, because the last good frame is exactly right for a canvas.
    public func evaluateEffects() -> [StoryboardSprite] {
        canvasSprites
    }

    /// What the canvas draws: the finished picture, or — while the camera is
    /// being edited — the world before the camera, so its frame can be drawn
    /// over what it will see.
    ///
    /// Only ever the canvas's. The export and `settledSprites()` read
    /// `evaluated`, which always carries the camera: the file is what the game
    /// shows, whatever mode the editor happens to be in.
    private var canvasSprites: [StoryboardSprite] {
        (isEditingCamera && !isViewingThroughCamera ? world : nil) ?? evaluated
    }

    /// Whether the canvas shows the finished picture while the camera is being
    /// edited, instead of the world with the frame over it.
    ///
    /// The frame says what will be in shot; this says what that shot looks
    /// like. Zooming in shrinks the frame — correct, since the camera sees
    /// less — and without a way to look through it the zoom cannot be judged
    /// without leaving the mode. Both pictures are already in hand, so
    /// switching pushes one or the other and evaluates nothing.
    public var isViewingThroughCamera = false {
        didSet {
            guard isViewingThroughCamera != oldValue else { return }
            onSpritesChanged?(canvasSprites)
        }
    }

    /// The last pass's sprites before the camera, kept only in camera mode.
    private var world: [StoryboardSprite]?

    /// Called whenever a new pass lands, so the canvas can take the sprites
    /// rather than asking for them.
    ///
    /// Pushed rather than pulled because the result no longer arrives when the
    /// edit does: reading a revision counter would tell a view that something
    /// changed at the moment the work *started*, which is a frame of emptiness
    /// before the sprites exist.
    @ObservationIgnored public var onSpritesChanged: (([StoryboardSprite]) -> Void)?

    /// The sprites for the document as it stands, waiting for any pass in
    /// flight.
    ///
    /// What a caller wants when the sprites are the *answer* rather than the
    /// picture — an export, a test. The canvas deliberately does not use this:
    /// there, the last good frame is right.
    public func settledSprites() async -> [StoryboardSprite] {
        await awaitEvaluation()
        return evaluated
    }

    /// The presets a placed clip could swap to.
    ///
    /// Empty for an effect that ships none, which is what hides the control
    /// rather than showing an empty menu.
    public func presets(forEffectType type: String) -> [EffectPreset] {
        presets.filter { $0.effectType == type }
    }

    /// Swaps a placed clip's preset, keeping what makes the clip itself.
    ///
    /// The reason this exists: picking a template, placing it, and then
    /// wanting to try a different movement on the *same* clip meant building
    /// it again — so only the preset's own overrides land, and the author's
    /// text, font, colour and size survive.
    ///
    /// Through the model so `EditHistory` sees it: this is an edit, and one
    /// somebody trying presets one after another needs to be able to take
    /// back.
    public func applyPreset(_ preset: EffectPreset, to nodeID: EffectNode.ID) {
        guard !isLocked(nodeID) else { return }

        effects.applyPreset(
            preset,
            to: nodeID,
            // Its siblings say which parameters a preset of this effect is
            // allowed to own, which is what keeps the swap from reaching into
            // the author's content.
            siblings: presets(forEffectType: preset.effectType),
            defaults: library.descriptor(for: preset.effectType)?.defaultValues,
        )
        effectsChanged(node: nodeID)
    }

    /// Presets available for the effects in the library.
    public var presets: [EffectPreset] {
        // Every effect's presets, filtered to what the library can actually
        // run. The panel groups them by `effectType`, so a new effect's presets
        // appear under it without any UI work.
        (TextEffect.presets + ShapeEffect.presets + AudioBarsEffect.presets + AudioWavesEffect.presets
            + EmitterEffect.presets + EmitterEffect.compoundPresets + TileWipeEffect.presets)
            .filter { library.descriptor(for: $0.effectType) != nil }
    }

    /// Presets grouped into the packs they belong to, in a stable order.
    public var packs: [(name: String, presets: [EffectPreset])] {
        let packed = presets.compactMap { preset -> (String, EffectPreset)? in
            guard let pack = preset.pack else { return nil }
            return (pack, preset)
        }

        var order: [String] = []
        var byPack: [String: [EffectPreset]] = [:]
        for (name, preset) in packed {
            if byPack[name] == nil { order.append(name) }
            byPack[name, default: []].append(preset)
        }

        return order.map { ($0, byPack[$0] ?? []) }
    }

    // ─── Placing ─────────────────────────────────────────────────────────────

    /// Where a new effect lands: the selected track, or a new one.
    private var destinationTrackID: EffectTrack.ID? {
        selectedTrack?.id ?? effects.tracks.last?.id
    }

    @discardableResult
    /// Gives a freshly placed script clip a file of its own.
    ///
    /// "Creating a clip creates a file; duplicating does not" — and without
    /// this half the panel has nothing to open: a placed clip showed "No
    /// script file" and no button, which is a clip nobody can edit.
    ///
    /// Placed separately means separate files. Sharing is what *duplicating*
    /// means; two clips placed one after the other are two independent things,
    /// and one overwriting the other would lose the first one's code the
    /// moment the second arrived.
    ///
    /// Called from both `addEffect` and `addPreset` rather than from
    /// `EffectDocument.add`, because Core has no folder — and from a helper
    /// rather than inline in each, because a second route that forgets is how
    /// this bug existed in the first place.
    private func placeScriptFile(for node: EffectNode) -> EffectNode {
        guard node.scriptFile == nil,
              let source = node.scriptSource,
              let projectFolder,
              let file = ScriptStore.availableName(like: node.name, inFolder: projectFolder)
        else { return node }

        // A folder that cannot take the file leaves the clip working from its
        // inline source: it draws, it just cannot be opened in an editor yet.
        // Refusing to place the clip at all would be worse.
        guard (try? ScriptStore.write(source, to: file, inFolder: projectFolder)) != nil else {
            return node
        }

        var placed = node
        placed.scriptFile = file
        effects[node.id] = placed

        // The declarations, so the editor has types the moment it opens — and
        // this is the first script in a project that had none.
        try? writeScriptTypesHandler?(projectFolder)
        refreshScriptSnippets()

        return placed
    }

    @discardableResult
    public func addEffect(
        _ descriptor: EffectDescriptor,
        at startTime: Double,
        duration: Double = 2000,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode {
        let node = effects.add(
            descriptor,
            at: startTime,
            duration: duration,
            on: trackID ?? destinationTrackID,
        )
        let placed = completingPlacement { placeScriptFile(for: node) }
        selectedNodeID = placed.id
        effectsChanged()
        return placed
    }

    /// Writes that finish a placement `effects.add` began, as part of its one
    /// undo step.
    ///
    /// The add records the document as it was before the clip existed — the
    /// state ⌘Z should return to. Every placement then fills the node in
    /// (name, values, layers, a script file) with further writes, and each
    /// write to `effects` records another snapshot. Placing a preset took two
    /// ⌘Z: the first left the clip at its defaults, somewhere the author never
    /// was — the gap in an undo stack this model's `willSet` exists to prevent.
    private func completingPlacement<T>(_ write: () -> T) -> T {
        var result: T?
        withoutRecording { result = write() }
        // The closure always runs; the force is the price of `withoutRecording`
        // taking no return value.
        return result!
    }

    /// Places a preset, using the length the preset asks for.
    ///
    /// The duration is the preset's rather than a fixed default because a burst
    /// and a stream want very different blocks: a shockwave lasts under a
    /// second, and stretching it over five leaves four of nothing.
    @discardableResult
    public func addPreset(
        _ preset: EffectPreset,
        at startTime: Double,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode? {
        guard let descriptor = library.descriptor(for: preset.effectType) else { return nil }

        var node = effects.add(
            descriptor,
            at: startTime,
            duration: preset.duration,
            on: trackID ?? destinationTrackID,
        )
        node.name = preset.name
        node.values = preset.values

        // A preset's position moves onto the transform, which is where position
        // lives now. Left in `values` it would be read by nothing and the
        // emitter would sit at the canvas centre whatever the preset said.
        if case let .number(x) = preset.values[EmitterEffect.Param.x] {
            node.transform[value: .x] = x
        }
        if case let .number(y) = preset.values[EmitterEffect.Param.y] {
            node.transform[value: .y] = y
        }

        // The preset's own layers, each a node in its own right.
        //
        // Built here rather than described in the preset because only this
        // knows how to make an id and a seed — and a seed that repeated across
        // layers would give two of them the same particle field.
        node.layers = preset.layers.enumerated().compactMap { index, layer in
            guard let layerDescriptor = library.descriptor(for: layer.effectType) else {
                return nil
            }
            var child = EffectNode(
                id: "\(node.id)/L\(index)",
                type: layer.effectType,
                name: layer.name,
                layer: node.layer,
                startTime: 0,
                duration: preset.duration,
                seed: EffectNode.layerSeed(from: node.seed, index: index),
                values: layerDescriptor.defaultValues.merging(layer.values) { _, new in new },
                delay: layer.delay > 0 ? layer.delay : nil,
            )
            // A layer's position is a transform too, for the same reason the
            // parent's is.
            if case let .number(x) = layer.values[EmitterEffect.Param.x] {
                child.transform[value: .x] = x
            }
            if case let .number(y) = layer.values[EmitterEffect.Param.y] {
                child.transform[value: .y] = y
            }
            return child
        }

        // Its filters, with ids of this clip's own. Minted here for the reason
        // the layers are: only placing knows what makes an id unique.
        node.filters = preset.filterNodes(using: filters) { index in
            "\(preset.filters[index].type)-\(UUID().uuidString.prefix(8))"
        }

        // A preset can be a script's too, so it takes the same route.
        let placed = completingPlacement {
            effects[node.id] = node
            return placeScriptFile(for: node)
        }

        selectedNodeID = placed.id
        effectsChanged()
        return placed
    }

    /// Places an image on the timeline.
    ///
    /// Its own method rather than a preset because the path is the point: an
    /// image effect with no file draws nothing, so the one thing it must be
    /// given is the thing an asset row already knows.
    @discardableResult
    public func addImage(
        at path: String,
        time: Double,
        duration: Double = 4000,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode? {
        guard let descriptor = library.descriptor(for: ImageEffect.descriptor.type) else {
            return nil
        }

        var node = effects.add(
            descriptor,
            at: time,
            duration: duration,
            on: trackID ?? destinationTrackID,
        )
        node.name = (path as NSString).lastPathComponent
        node.values[ImageEffect.Param.sprite] = .text(path)
        completingPlacement { effects[node.id] = node }

        selectedNodeID = node.id
        effectsChanged()
        return node
    }

    /// Places an asset by what it is: a sound becomes a sample, anything else
    /// an image. One door for the double-click and the drop, so they cannot
    /// disagree about which is which.
    @discardableResult
    public func placeAsset(
        at path: String,
        time: Double,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode? {
        switch AssetItem.Kind.inferred(from: path) {
        case .audio: addSample(at: path, time: time, on: trackID)
        default: addImage(at: path, time: time, on: trackID)
        }
    }

    /// The effects the blank-effect menu may offer.
    ///
    /// A sound is left out: without a file it means nothing, and it is made by
    /// placing an audio asset.
    public var creatableDescriptors: [EffectDescriptor] {
        library.descriptors.filter(\.isCreatableBlank)
    }

    /// Opens a clip's keyframes, selecting it too.
    ///
    /// A clip that draws nothing has nothing to animate, so the mode refuses it
    /// here — in the model, so no gesture can open an empty editor.
    public func openKeyframes(of nodeID: EffectNode.ID) {
        guard let node = effects[nodeID],
              library.descriptor(for: node)?.drawsSprites ?? true
        else { return }
        selectedNodeID = nodeID
        keyframeNodeID = nodeID
    }

    /// Places a sound on the timeline.
    ///
    /// The clip is as long as its file, asked of the app through
    /// `audioDuration` once, here. If that cannot say — no seam, an
    /// undecodable file — it is placed anyway with a short marker length: a
    /// sound the platform cannot measure is still a sound the game can play.
    @discardableResult
    public func addSample(
        at path: String,
        time: Double,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode? {
        guard let descriptor = library.descriptor(for: SampleEffect.descriptor.type) else {
            return nil
        }

        let seconds = audioDuration?(path)
        let duration: Double = if let seconds, seconds.isFinite, seconds > 0 {
            seconds * 1000
        } else {
            SampleEffect.fallbackDuration
        }

        var node = effects.add(
            descriptor,
            at: max(0, time),
            duration: duration,
            on: trackID ?? destinationTrackID,
        )
        node.name = (path as NSString).lastPathComponent
        node.values[SampleEffect.Param.file] = .text(path)
        completingPlacement { effects[node.id] = node }

        selectedNodeID = node.id
        effectsChanged()
        return node
    }

    // ─── Lyrics ──────────────────────────────────────────────────────────────

    /// Reads the song and returns the words it heard.
    ///
    /// Supplied by the app for the same reason the video export is: the speech
    /// framework belongs to the platform layer, and a feature does not import
    /// another. It takes the audio URL rather than reading it from playback —
    /// `PlaybackModel` is `@MainActor`, so a closure touching it would hop to
    /// the main thread and drag seconds of audio decoding along.
    @ObservationIgnored
    public var lyricTranscriptionHandler: (
        @Sendable (_ audio: URL, _ locale: String) async throws -> [LyricTranscription.Word]
    )?

    /// The song to transcribe, set by whoever loaded it.
    @ObservationIgnored public var lyricAudioURL: URL?

    /// Which languages the engine can do, and which are already downloaded.
    ///
    /// Supplied by the app alongside the transcriber. Told apart because the
    /// distinction decides how long the next click takes: an installed
    /// language starts in seconds, and any other one fetches a model first.
    @ObservationIgnored
    public var lyricLocalesHandler: (
        @Sendable () async -> (available: [String], installed: [String])
    )?

    /// The languages to offer, grouped and named by the app.
    ///
    /// Supplied rather than derived: grouping needs `Locale` and the engine's
    /// own list, and this target imports neither.
    @ObservationIgnored
    public var lyricLanguagesHandler: (
        @Sendable () async -> [LyricTranscription.LanguageOption]
    )?

    /// The languages to offer, or nothing when no engine is installed.
    public func lyricLocales() async -> (available: [String], installed: [String]) {
        guard let lyricLocalesHandler else { return ([], []) }
        return await lyricLocalesHandler()
    }

    /// How long a line may run before it is treated as more than one sentence.
    ///
    /// On the model rather than the panel's `@State` so it survives the panel
    /// being rebuilt, which happens whenever the playhead moves.
    public var lyricMaximumDuration = LyricTranscription.maximumLineDuration

    /// The gap that ends a line.
    public var lyricGapThreshold = LyricTranscription.defaultGapThreshold

    /// How big the placed text is, as the clip's **scale**.
    ///
    /// The transform's scale rather than the font size, and the reason is the
    /// atlas: `TextSprite.rawPath` hashes the size into each glyph's path, so
    /// every size tried mints a fresh texture for every character — a hundred
    /// and eleven of them in one song, and a slider dragged across its range
    /// would coin a set per step. A scale is one `_V` command and the texture
    /// never changes.
    ///
    /// One number for both axes: lyrics are read, not stretched. An author who
    /// wants one axis has the inspector.
    public var lyricScale: Double = 1

    /// How placed lines use the moment each word was sung.
    public enum LyricWordTiming: String, CaseIterable, Sendable {
        /// The preset's own sequence: the words carry their timing, unused.
        case off = "Off"
        /// Each word appears as it is sung.
        case reveal = "Reveal"
        /// The whole line on screen, each word lighting as it is sung.
        case highlight = "Highlight"
    }

    /// Karaoke, for lines that know when their words were sung.
    ///
    /// Applied after the preset, like the text: a preset brings its own
    /// stagger and colour, and the point of choosing karaoke is that the song
    /// decides those instead.
    public var lyricWordTiming: LyricWordTiming = .off

    /// Whether the lines in the panel know their words' timing — a
    /// transcription, or a `.srt` timed by word. One timed by line does not,
    /// and karaoke has nothing to work from.
    public var lyricLinesHaveWordTiming: Bool {
        lyricLines.contains { !$0.words.isEmpty }
    }

    /// Which lines have already been placed.
    ///
    /// So a line can be given its own movement — place one, change the preset,
    /// place the next — without losing track of what is already on the
    /// timeline. Cleared with the transcription it belongs to.
    public private(set) var placedLyricLines: Set<Double> = []

    /// Places one line, so it can carry a movement of its own.
    public func importLyricLine(_ line: LyricTranscription.Line, preset: EffectPreset? = nil) {
        importLyrics([line], preset: preset, into: .selectionOrNew)
        placedLyricLines.insert(line.id)
    }

    /// Regroups with whatever the two knobs currently say.
    public func regroupLyrics() {
        guard !lyricWords.isEmpty else { return }
        lyricLines = LyricTranscription.lines(
            from: lyricWords,
            gapThreshold: lyricGapThreshold,
            maximumDuration: lyricMaximumDuration,
        )
        // The lines are new objects, so what was placed no longer describes
        // them: leaving the marks would tick rows that were never placed.
        placedLyricLines = []
    }

    /// What the last transcription heard, grouped into lines.
    ///
    /// Held rather than placed. A transcription is a **draft** — measured, six
    /// per cent of Japanese lines and forty per cent of English ones want
    /// checking — and thirty-eight clips appearing unbidden is not a draft.
    public private(set) var lyricLines: [LyricTranscription.Line] = []

    /// The words behind ``lyricLines``, kept so the grouping can be retuned
    /// without reading the song again.
    @ObservationIgnored private var lyricWords: [LyricTranscription.Word] = []

    /// Whether a transcription is running.
    public private(set) var isTranscribingLyrics = false

    /// Why the last transcription failed, if it did.
    ///
    /// Reported rather than swallowed: a transcription that returns nothing and
    /// says nothing is indistinguishable from a song with no singing in it.
    public private(set) var lyricError: String?

    public var canTranscribeLyrics: Bool {
        lyricTranscriptionHandler != nil && !isTranscribingLyrics
    }

    /// Transcribes the loaded song into ``lyricLines``.
    public func transcribeLyrics(locale: String) async {
        guard let lyricTranscriptionHandler, !isTranscribingLyrics else { return }

        isTranscribingLyrics = true
        lyricError = nil
        defer { isTranscribingLyrics = false }

        // A missing URL is not a failure worth a message: nothing is loaded
        // yet, and the button that led here should not have been reachable.
        let audio = lyricAudioURL ?? URL(fileURLWithPath: "")

        do {
            lyricWords = try await lyricTranscriptionHandler(audio, locale)
            lyricLines = LyricTranscription.lines(
                from: lyricWords,
                gapThreshold: lyricGapThreshold,
                maximumDuration: lyricMaximumDuration,
            )
            placedLyricLines = []
            lyricSource = .transcription
        } catch {
            lyricWords = []
            lyricLines = []
            lyricError = "\(error)"
            lyricSource = nil
        }
    }

    /// Regroups with an explicit gap, for callers that pass one.
    ///
    /// Reading the song again to change a number would cost seconds for an
    /// answer already in hand — the words stay in memory for exactly this.
    public func regroupLyrics(gapThreshold: Double) {
        lyricGapThreshold = gapThreshold
        regroupLyrics()
    }

    /// Forgets the last transcription.
    public func clearLyrics() {
        lyricWords = []
        lyricLines = []
        lyricError = nil
        placedLyricLines = []
        lyricSource = nil
    }

    // ─── Lyrics from a subtitle file ─────────────────────────────────────────

    /// Where ``lyricLines`` came from.
    public enum LyricSource: Equatable, Sendable {
        /// Heard in the song: a draft, with confidences and words to regroup.
        case transcription
        /// Read from a `.srt`: somebody's timing done by hand.
        ///
        /// A file timed by line is kept exactly. One timed by word —
        /// karaoke-style, a cue per word — is grouped into lines like a
        /// transcription, so its grouping knobs apply.
        case subtitles(name: String, byWord: Bool)
    }

    /// What the lines in the panel are, so it can offer only what applies to
    /// them — the grouping knobs fix a machine's guesses, and a subtitle file
    /// has none.
    public private(set) var lyricSource: LyricSource?

    /// Larger than any real subtitle file by a wide margin — a feature-length
    /// film's is around a hundred kilobytes. The cap is so that picking the
    /// wrong file does not read a video into memory to find no cues in it.
    public static let maximumSubtitleBytes = 4 * 1024 * 1024

    /// Reads a `.srt` into ``lyricLines``, ready to place with a movement.
    ///
    /// A failure keeps the lines already there: picking the wrong file is a
    /// slip, and should not cost the draft somebody was working through.
    public func loadSubtitles(from url: URL) {
        let name = url.lastPathComponent

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > Self.maximumSubtitleBytes {
            lyricError = "\(name) is too large to be a subtitle file."
            return
        }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            lyricError = "\(name) could not be read."
            return
        }
        // UTF-8 first, which is nearly every file; older subtitle files are
        // often Windows-1252, and reading them as UTF-8 fails outright rather
        // than garbling, so the fallback is never reached by a good file.
        // UTF-16 only behind its BOM: without one, any even-length buffer
        // "decodes" — measured, a Windows-1252 file came back as garbage
        // instead of reaching the fallback below it.
        let hasUTF16BOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        guard let text = String(data: data, encoding: .utf8)
            ?? (hasUTF16BOM ? String(data: data, encoding: .utf16) : nil)
            ?? String(data: data, encoding: .windowsCP1252)
        else {
            lyricError = "\(name) is not a text file."
            return
        }

        let cues = SubtitleParser.lines(from: text)
        guard !cues.isEmpty else {
            lyricError = "\(name) has no timed lines in it."
            return
        }

        let byWord = SubtitleParser.isTimedByWord(cues)
        if byWord {
            lyricWords = SubtitleParser.words(from: cues)
            lyricLines = LyricTranscription.lines(
                from: lyricWords,
                gapThreshold: lyricGapThreshold,
                maximumDuration: lyricMaximumDuration,
            )
        } else {
            // No words: the lines are the author's, so `regroupLyrics` has
            // nothing to work from and leaves them alone.
            lyricWords = []
            lyricLines = cues
        }
        lyricError = nil
        placedLyricLines = []
        lyricSource = .subtitles(name: name, byWord: byWord)
    }


    /// Places transcribed lines as text clips, one per line.
    ///
    /// The half of a lyric storyboard nobody can do by hand: the words are a
    /// search away, and marking four hundred glyphs to twenty milliseconds is
    /// not. What arrives is ordinary clips — they carry a transform, keyframes,
    /// filters, undo and the project format, none of which had to be invented
    /// for this.
    ///
    /// - Parameters:
    ///   - lines: what was heard, in song time. Grouping words into these is
    ///     ``LyricTranscription/lines(from:gapThreshold:maximumCharacters:)``.
    ///   - preset: the movement to give them. Nothing forces one, and nothing
    ///     should: thirty-eight clips with every animation parameter resting at
    ///     zero are thirty-eight captions, and a preset is only a bag of values
    ///     so this costs nothing.
    public func importLyrics(
        _ lines: [LyricTranscription.Line],
        preset: EffectPreset? = nil,
        into destination: LyricDestination = .newTrack,
    ) {
        guard !lines.isEmpty else { return }
        guard let descriptor = library.descriptor(for: TextEffect.descriptor.type) else { return }

        // One undo entry and one evaluation for the whole import.
        //
        // Placing thirty-eight clips one at a time records thirty-eight undo
        // steps — so taking the import back is thirty-eight keystrokes, each
        // showing a half-imported song — and starts thirty-eight evaluations
        // that cancel each other. This is the same bracket a drag uses, for the
        // same reason: what somebody wants back is the state before the
        // gesture, not one clip ago.
        // `beginGesture` coalesces the undo entry and holds evaluation until
        // the whole batch is in; `effectsChanged` is what says the document
        // moved. Both are needed — `endGesture` only re-evaluates, so without
        // the second the revision stayed at zero: the canvas was never told
        // there were new sprites, the title bar never showed unsaved changes,
        // and every revision-keyed cache kept a pre-import answer.
        beginGesture()
        defer {
            endGesture()
            effectsChanged()
        }

        let trackID = lyricsTrackID(for: destination)

        for line in lines {
            var node = effects.add(
                descriptor,
                // Song time, which is what a line carries and what a clip
                // wants: the effect generates in local time and the evaluator
                // adds this offset once.
                at: line.start,
                duration: max(line.duration, Self.minimumLyricDuration),
                on: trackID,
            )

            // The line is the name. `add` numbers duplicates — "Text 2", "Text
            // 3" — which says nothing about which line a clip holds, and
            // thirty-eight of those are a track nobody can read.
            node.name = Self.clipName(for: line.text)

            // The preset first, then the text: a preset carries values for
            // every parameter it touches, and applying it afterwards would
            // overwrite the one thing that makes this clip itself.
            if let preset {
                node.values.merge(preset.values) { _, new in new }
            }
            node.values[TextEffect.Param.text] = .text(line.text)

            // Every line that knows its words keeps them, whatever the panel
            // says: switching a placed clip to karaoke later is then a choice
            // in the inspector rather than a re-import.
            if !line.words.isEmpty {
                node.sungWords = SungTiming.words(from: line.words, clipStart: line.start)
                switch lyricWordTiming {
                case .off:
                    break
                case .reveal:
                    node.values[TextEffect.Param.staggerMode] = .choice(SungTiming.choice)
                    // By word, because that is the unit a singer reaches.
                    // Character spreads each word's letters across it, and is
                    // one change away in the inspector.
                    node.values[TextEffect.Param.unit] = .choice("Word")
                case .highlight:
                    node.values[TextEffect.Param.colourMode] = .choice("Highlight")
                    node.values[TextEffect.Param.sweepOrder] = .choice(SungTiming.choice)
                }
            }

            // Applied here rather than left to the inspector: at full size a
            // line of twenty-five glyphs is 1200 points on a stage 854 wide,
            // so without this every clip had to be resized by hand — which is
            // the work this feature exists to remove.
            if lyricScale != 1 {
                node.transform[value: .scaleX] = lyricScale
                node.transform[value: .scaleY] = lyricScale
            }

            effects[node.id] = node
        }
    }

    /// A clip's label: the line, shortened to something a track row can show.
    ///
    /// Truncated rather than wrapped or dropped — the first few words are
    /// enough to tell one line from another, which is all a label is for.
    private static func clipName(for text: String) -> String {
        guard text.count > maximumClipNameLength else { return text }
        return text.prefix(maximumClipNameLength).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static let maximumClipNameLength = 24

    /// What a lyric clip lasts when the engine reported no length at all.
    ///
    /// A glyph can come back as a single instant, and a zero-length clip cannot
    /// be grabbed on the timeline — `TextEffect` also guards on
    /// `context.duration > 0`, so it would draw nothing at all.
    private static let minimumLyricDuration: Double = 200

    /// The name for a new lyrics lane, numbered if one is already there.
    /// Where placed lyric clips go.
    ///
    /// Passed rather than decided inside, because the two callers want
    /// opposite things and the batch's reasoning does not transfer to a single
    /// line — which is how the per-line button came to open a lane per click.
    public enum LyricDestination: Sendable {
        /// A lane of its own, every time. What **Place All** wants: a second
        /// batch — another language, or a corrected pass — piled into the
        /// first would overlap it and leave neither pickable.
        case newTrack

        /// The selected lane, or a new one when nothing is selected.
        ///
        /// What placing one line wants. Ten clicks gave ten lanes named
        /// `Lyrics` through `Lyrics 10`, which is unusable for the thing the
        /// button exists to do — and with a lane selected, that selection is
        /// the only statement of intent there is.
        case selectionOrNew
    }

    private func lyricsTrackID(for destination: LyricDestination) -> EffectTrack.ID {
        if case .selectionOrNew = destination,
           let selectedTrackID,
           effects.track(id: selectedTrackID) != nil
        {
            return selectedTrackID
        }
        let track = effects.addTrack(named: lyricsTrackName())
        // Selected, the way `addTrack` does it for a lane made by hand.
        //
        // Without this the second line placed found nothing selected and made
        // its own lane, and the third did it again — so `.selectionOrNew` fixed
        // the case with a lane already picked and left the ordinary one, an
        // empty project, giving a lane per click.
        selectedTrackID = track.id
        return track.id
    }

    private func lyricsTrackName() -> String {
        let base = "Lyrics"
        let existing = effects.tracks.count { $0.name == base || $0.name.hasPrefix("\(base) ") }
        return existing == 0 ? base : "\(base) \(existing + 1)"
    }

    // ─── Editing effects ─────────────────────────────────────────────────────

    // ─── Clipboard ───────────────────────────────────────────────────────────

    // ─── Saving ──────────────────────────────────────────────────────────────

    /// Where the timeline is looking, kept so it can be saved and restored.
    ///
    /// On the model rather than left in the view: the view's own `@State` is
    /// gone by the time a project is written, and a window someone spent time
    /// arranging is worth reopening as they left it.
    @ObservationIgnored public var timelineView: Project.TimelineView?

    /// Where this project is saved, once it has a home.
    public var projectFolder: URL?

    /// Set when a project exists on disk but could not be read.
    ///
    /// Saving is refused while this is true. A file that failed to open is
    /// still someone's work, and writing an empty document over it turns a bug
    /// that could be fixed into a project that is gone.
    public private(set) var loadFailed = false

    /// Whether anything has changed since the last save.
    public private(set) var hasUnsavedChanges = false

    /// The last save's outcome, for the UI to show.
    public private(set) var saveError: String?

    /// Loads a project from a beatmap folder, if it has one.
    ///
    /// Silent when there is none: most folders have never been opened here, and
    /// that is the ordinary case rather than a failure.
    public func loadProject(fromFolder folder: URL) {
        projectFolder = folder
        loadFailed = false
        do {
            guard let project = try ProjectFile.read(fromFolder: folder) else { return }
            // Scripts written before they had files hold their code in the
            // `.aesb`, which was the only place it existed — so it moves out to
            // disk here, on the one path that has the folder.
            //
            // A failure is swallowed on purpose: the code is still in the
            // document, so the clip keeps working from its resolved source, and
            // refusing to open would lose a whole project over a permission on
            // one file. The next save writes the old key, so nothing is lost by
            // trying again later.
            let document = (try? ScriptStore.migrate(project.document, inFolder: folder))
                ?? project.document
            // Cleared before the write, and the write itself is not recorded.
            //
            // Undoing into the previous beatmap's document would restore
            // effects belonging to a different map — worse than having no undo
            // at all, because it looks like it worked.
            history.clear()
            withoutRecording { effects = document }
            timelineView = project.view
            selectedNodeID = nil
            selectedTrackID = effects.tracks.last?.id
            effectsChanged()
            // After migration, so a v1 project's freshly written scripts get
            // their declarations too — and only when there is a script to read
            // them: two generated files nothing references would land in the
            // mapper's published beatmap folder for nothing.
            //
            // A failure is ignored on purpose. These exist for an external
            // editor to read, so a folder that cannot take them costs
            // autocompletion, not the project.
            if document.nodes.contains(where: { $0.scriptFile != nil }) {
                try? writeScriptTypesHandler?(folder)
            }

            // Through the same helper, which stops the previous project's
            // watcher first: left running, it would reload this project every
            // time someone edited a script in the folder they just closed.
            startWatchingScripts()
            refreshScriptSnippets()
            // Loading is not a change: a project opened and closed untouched
            // should not claim to need saving.
            hasUnsavedChanges = false
            saveError = nil
        } catch {
            loadFailed = true
            saveError = "Could not open the project in this folder: \(error)"
        }
    }

    @discardableResult
    public func saveProject() -> Bool {
        guard let projectFolder, !loadFailed else { return false }
        do {
            try ProjectFile.write(
                Project(document: effects, view: timelineView),
                toFolder: projectFolder,
            )
            hasUnsavedChanges = false
            saveError = nil
            return true
        } catch {
            saveError = String(describing: error)
            return false
        }
    }

    // ─── Exporting ───────────────────────────────────────────────────────────

    /// Writes the storyboard out, if someone has wired up how.
    ///
    /// The shell does not export it itself: the images an export has to write
    /// are the renderer's, and a feature cannot import another. So the app —
    /// which already connects the canvas to the shell — supplies this, the same
    /// way it supplies everything else that crosses that line.
    ///
    /// Takes the evaluated sprites and the folder, and returns where it wrote
    /// to, or throws.
    @ObservationIgnored
    /// Renders what something does, as frames, if the app supplies them.
    ///
    /// Provided from outside for the same reason the export is: drawing needs
    /// the renderer, and this feature is layout rather than behaviour. Optional
    /// so the shell runs without it — a panel with no pictures is a panel, a
    /// panel that cannot be built is not.
    /// The song's beat, for effects that follow it.
    ///
    /// Set by whoever owns playback, because the timing comes off the beatmap
    /// and this feature never opens one. An effect asks the evaluator, which
    /// asks this — so a pulse needs no BPM typed into it.
    public var beat: BeatGrid? {
        didSet {
            // The app assigns the beat when the window appears and again when
            // the track loads, and every assignment dropped every clip — the
            // scripts with them — for a grid that had not changed.
            guard beat != oldValue else { return }
            evaluator.beat = beat
            inputsChanged()
        }
    }

    // ─── Nudging the playhead ────────────────────────────────────────────────

    /// Which grid an arrow key steps along.
    public enum PlayheadStep: Sendable {
        /// One beat — what an arrow key does.
        case beat
        /// One bar — what shift and an arrow key do.
        case bar
    }

    /// Moves the playhead one step earlier or later.
    ///
    /// Stepping by *beat* rather than by a fixed number of milliseconds,
    /// because the map already declares its tempo: the playhead lands where
    /// things get placed in a rhythm game, and it stays landed as the tempo
    /// changes. A fixed step reaches a beat only by accident, and then only
    /// until the next timing point.
    ///
    /// Falls back to a fixed step when a map has no timing points at all —
    /// arrow keys that do nothing on a map missing its BPM would read as the
    /// editor being broken rather than as the map being incomplete.
    public func nudgePlayhead(by step: PlayheadStep, forward: Bool) {
        guard let seekHandler else { return }
        let now = playheadTime
        let target = nudgeTarget(from: now, by: step, forward: forward)
        // Clamped to the piece rather than to the song: a storyboard can open
        // before zero and run past the end of the track.
        let range = playedTimeRange ?? 0...now
        seekHandler(min(max(range.lowerBound, target), range.upperBound))
    }

    /// Where a nudge lands, in absolute time.
    private func nudgeTarget(
        from now: Double,
        by step: PlayheadStep,
        forward: Bool,
    ) -> Double {
        guard let beat, !beat.isEmpty else {
            return now + (forward ? 1 : -1) * Self.fixedNudge
        }

        switch step {
        case .beat:
            return forward ? beat.nextBeat(after: now) : beat.previousBeat(before: now)
        case .bar:
            // Downbeats come from the same lines the ruler draws, so a bar
            // step and a bar mark cannot disagree about where a measure
            // begins.
            //
            // Searched over a window rather than the whole track: `lines(in:)`
            // walks every beat in the range it is given, and a five-minute
            // song at speed is tens of thousands of them for one keystroke.
            let window = Self.barSearchWindow
            let range = forward ? now...(now + window) : (now - window)...now
            let bars = beat.lines(in: range).filter(\.isMajor)
            let found = forward
                ? bars.first { $0.time > now + 0.5 }?.time
                : bars.last { $0.time < now - 0.5 }?.time
            // No downbeat within the window — a very slow tempo, or the end of
            // the track. A beat is a smaller move than asked for and a much
            // better answer than standing still.
            return found ?? nudgeTarget(from: now, by: .beat, forward: forward)
        }
    }

    /// The step for a map with no timing points, in milliseconds.
    ///
    /// About one frame at 60fps: fine enough to adjust an instant, and the
    /// only honest answer when nothing declares a tempo.
    private static let fixedNudge: Double = 16

    /// How far ahead a bar step looks for a downbeat.
    ///
    /// Eight seconds is several bars at any tempo anyone writes, and bounds
    /// the work a keystroke does on a long track.
    private static let barSearchWindow: Double = 8000

    public var previewImage: ((PreviewSubject) -> [CGImage])?

    // ─── Sprite thumbnails ───────────────────────────────────────────────────

    /// Draws a small picture of a built-in sprite, for the sprite picker.
    ///
    /// A seam like `previewImage`: the pictures are the renderer's, and a
    /// feature does not import another. Called off the main thread, so it has
    /// to be safe there — the app's is a decode from a locked cache.
    public var spriteThumbnail: (@Sendable (String) -> CGImage?)?

    /// The thumbnails that have landed, by path. Observed, so a tile redraws
    /// when its picture arrives; written only when one does.
    public private(set) var spriteThumbnails: [String: CGImage] = [:]

    /// Paths already asked for, landed or not — so a tile scrolled back into
    /// view does not decode again, and one with no picture is not retried on
    /// every appearance.
    @ObservationIgnored private var requestedSpriteThumbnails: Set<String> = []

    /// Asks for a thumbnail, decoded off the main thread.
    ///
    /// Sixty decodes in a row on the main thread are a visible hitch when the
    /// picker opens, so each tile asks as it appears and the picture lands
    /// when it is ready.
    public func requestSpriteThumbnail(_ path: String) {
        guard !requestedSpriteThumbnails.contains(path), let make = spriteThumbnail else { return }
        requestedSpriteThumbnails.insert(path)
        Task.detached(priority: .utility) { [weak self] in
            guard let image = make(path) else { return }
            await MainActor.run { self?.spriteThumbnails[path] = image }
        }
    }

    /// The picker's view of the thumbnails: read and request, nothing else.
    package var spriteThumbnailSource: SpriteThumbnails {
        SpriteThumbnails(
            image: { [weak self] in self?.spriteThumbnails[$0] },
            request: { [weak self] in self?.requestSpriteThumbnail($0) },
        )
    }

    // ─── Library previews ────────────────────────────────────────────────────

    /// The previews the library's cards have been given, by `PreviewSubject.key`.
    ///
    /// Observed, so a card redraws when its frames land; written only by the
    /// queue below, never during a view's body.
    public private(set) var previews: [String: [CGImage]] = [:]

    /// The frames a card has been given, or none yet.
    public func preview(of subject: PreviewSubject) -> [CGImage] {
        previews[subject.key] ?? []
    }

    /// Subjects waiting for a preview, in the order their cards appeared.
    @ObservationIgnored private var pendingPreviews: [PreviewSubject] = []
    @ObservationIgnored private var previewQueue: Task<Void, Never>?

    /// Asks for a preview, rendered when its turn comes.
    ///
    /// Called as a card appears, so only what is on screen is ever rendered.
    /// One preview per main-actor turn with a yield between them: a preview
    /// sets up the renderer on the main thread, and fifty of them back to back
    /// would hold the window for seconds — the panel would open frozen. Spread
    /// out, the cards fill in one after another while the panel stays live.
    ///
    /// One queue for presets and filters alike: they share the renderer, and
    /// two queues would each yield to the other's work rather than to the UI.
    public func requestPreview(for subject: PreviewSubject) {
        let key = subject.key
        guard previews[key] == nil,
              !pendingPreviews.contains(where: { $0.key == key }),
              previewImage != nil
        else { return }

        pendingPreviews.append(subject)
        guard previewQueue == nil else { return }

        previewQueue = Task { [weak self] in
            while let self, !self.pendingPreviews.isEmpty {
                await Task.yield()
                let subject = self.pendingPreviews.removeFirst()
                // An empty result is kept too: something that draws nothing at
                // preview size must not be asked for again on every scroll.
                self.previews[subject.key] = self.previewImage?(subject) ?? []
            }
            self?.previewQueue = nil
        }
    }

    /// Writes the storyboard and everything it needs. Takes the document's
    /// samples beside the sprites: a sound is not a sprite, and the file holds
    /// both.
    public var exportHandler: ((
        _ sprites: [StoryboardSprite],
        _ samples: [StoryboardSample],
        _ folder: URL,
    ) throws -> URL)?

    /// The length, in seconds, of an audio file named by a path relative to
    /// the project, or `nil` when it cannot be read.
    ///
    /// A seam like `exportHandler`: reading a file's length needs
    /// AVFoundation, which Core does not import. Asked once, at placement —
    /// a sample's length is its file's and moving the clip never changes it.
    @ObservationIgnored
    public var audioDuration: (@Sendable (_ path: String) -> Double?)?

    /// Writes the editor's type declarations into a project folder.
    ///
    /// A seam like `exportHandler`, and for the same reason: the declarations
    /// are derived from what the script engine installs, and this target
    /// deliberately does not depend on it — `StoryboardScripting` imports
    /// JavaScriptCore, and the shell is arrangement rather than runtime. The
    /// app connects the two, at the same seam where it already connects the
    /// canvas and the export.
    ///
    /// Optional, so the shell runs without one: a folder with no declarations
    /// is a folder whose scripts have no autocompletion, which is a degraded
    /// editor rather than a broken app.
    @ObservationIgnored
    public var writeScriptTypesHandler: ((_ folder: URL) throws -> Void)?

    /// Starts watching a project folder for script edits, returning a stop.
    ///
    /// A seam for the same reason as the one above: the watcher belongs to the
    /// persistence layer and this target does not depend on it. The app
    /// connects them.
    ///
    /// The handler is handed a closure to call when scripts change, and gives
    /// back the way to stop — so this model never holds a platform object, and
    /// a shell with no handler installed simply does not auto-reload.
    ///
    /// Setting it starts watching straight away when a project is already
    /// open. Waiting for the next load is what the app actually did — the
    /// handlers are installed further down the same `.onAppear` that loads the
    /// project, so this was still `nil` when the load consulted it and the
    /// watcher was **never installed**. Every test passed, because every test
    /// installs its handlers first.
    ///
    /// A model that only works when its seams are filled in the right order
    /// fails silently the moment someone moves a line, so it does not depend
    /// on the order.
    @ObservationIgnored
    public var watchScriptsHandler: ((_ folder: URL, _ changed: @escaping @Sendable () -> Void) -> (() -> Void))? {
        didSet { startWatchingScripts() }
    }

    /// Whether a watcher is running for the project currently open.
    public var isWatchingScripts: Bool { stopWatchingScripts != nil }

    /// Starts watching the open project's folder, replacing any watcher.
    ///
    /// One place, called from the load and from the handler landing, because
    /// two copies of "start the watcher" is how one of them ends up not being
    /// called.
    private func startWatchingScripts() {
        stopWatchingScripts?()
        stopWatchingScripts = nil

        guard let projectFolder, let watchScriptsHandler else { return }
        stopWatchingScripts = watchScriptsHandler(projectFolder) { [weak self] in
            Task { @MainActor in self?.reloadScripts() }
        }
    }

    /// Stops the watcher started for the project currently open.
    @ObservationIgnored
    private var stopWatchingScripts: (() -> Void)?

    /// Hands a script file to whatever editor the author uses.
    ///
    /// Returns whether anything took it. A seam because launching belongs to
    /// AppKit, and because "whatever editor" is a decision for the app rather
    /// than for the shell: this target should not know that VSCode exists.
    @ObservationIgnored
    public var openScriptHandler: ((_ file: URL) -> Bool)?

    /// The first lines of each script file, by file name, for the library's
    /// script cards.
    ///
    /// Read on the few events that can change them — a project opening, the
    /// watcher reporting an edit, a script placed or renamed — and never from
    /// a view's body: a card redraws far more often than a file changes.
    @ObservationIgnored private var scriptSnippets: [String: [String]] = [:]
    /// Script files a clip names that are not on disk.
    @ObservationIgnored private var missingScripts: Set<String> = []
    /// The `.js` files in the project folder, clip or no clip.
    ///
    /// The Scripts tab lists files, not clips: removing the last clip that ran
    /// a script left the file on disk and took its card away, so the only way
    /// back to it was the Finder.
    @ObservationIgnored private var folderScripts: [ScriptFile] = []
    /// Bumped when the two above change, so the cards reading them redraw.
    public private(set) var scriptsRevision = 0

    /// Sets which file a script node reads.
    ///
    /// Through the model so `EditHistory` sees it: pointing a clip at another
    /// file is an edit, unlike a reload, and one the author has to be able to
    /// take back.
    public func setScriptFile(_ file: ScriptFile, on nodeID: EffectNode.ID) {
        guard var node = effects[nodeID], !isLocked(nodeID) else { return }
        guard node.scriptFile != file else { return }

        node.scriptFile = file
        effects[nodeID] = node
        effectsChanged(node: nodeID)
    }

    // ─── Script library ──────────────────────────────────────────────────────

    /// The project's script files, one entry per file rather than per clip.
    ///
    /// Per file because the file is what a script *is*: two clips sharing one
    /// run the same code, and editing it reloads both. Listed in the order
    /// their first clip appears on the timeline.
    public var scriptEntries: [ScriptEntry] {
        _ = scriptsRevision

        var byFile: [String: (file: ScriptFile, clips: [(EffectNode, EffectTrack.ID, Int)])] = [:]
        var order = 0
        for track in effects.tracks {
            for node in track.nodes {
                guard let file = node.scriptFile else { continue }
                byFile[file.name, default: (file, [])].clips.append((node, track.id, order))
                order += 1
            }
        }

        let placed = byFile.values
            .map { entry in
                // Earliest on the timeline; document order breaks a tie, so
                // the answer never depends on dictionary iteration.
                let clips = entry.clips.sorted {
                    ($0.0.startTime, $0.2) < ($1.0.startTime, $1.2)
                }
                return ScriptEntry(
                    file: entry.file,
                    snippet: scriptSnippets[entry.file.name] ?? [],
                    isMissing: missingScripts.contains(entry.file.name),
                    clipIDs: clips.map(\.0.id),
                    trackID: clips.first?.1,
                )
            }
            .sorted {
                let first = effects[$0.clipIDs[0]]?.startTime ?? 0
                let second = effects[$1.clipIDs[0]]?.startTime ?? 0
                return (first, $0.file.name) < (second, $1.file.name)
            }

        // After the placed ones, by name: with no clip there is no moment on
        // the timeline to order them by. `folderScripts` is already sorted.
        let unplaced = folderScripts
            .filter { byFile[$0.name] == nil }
            .map { file in
                ScriptEntry(
                    file: file,
                    snippet: scriptSnippets[file.name] ?? [],
                    isMissing: false,
                    clipIDs: [],
                    trackID: nil,
                )
            }
        return placed + unplaced
    }

    /// Why a script's last run failed, if any of its clips' did.
    ///
    /// Only failures count. A truncated run still drew, and a card turning red
    /// for "kept 2000 of 2400 sprites" would cry wolf on a script that works.
    public func scriptFailure(of entry: ScriptEntry) -> String? {
        for id in entry.clipIDs {
            for diagnostic in scriptReport?(id)?.diagnostics ?? [] {
                switch diagnostic {
                case let .compileFailed(message), let .runtimeFailed(message): return message
                case .noSource: return "The file is missing or empty."
                default: continue
                }
            }
        }
        return nil
    }

    /// Places another clip running an existing script file.
    ///
    /// Not `addEffect`: that writes a new file for every script clip it
    /// places, and the point here is the opposite — a second clip sharing the
    /// first's code, so editing the file changes both. An ordinary edit, so
    /// undo takes it back like any placement.
    @discardableResult
    public func addScriptClip(using file: ScriptFile, at startTime: Double) -> EffectNode? {
        guard let descriptor = library.descriptor(for: ScriptEffect.descriptor.type) else { return nil }

        var node = effects.add(descriptor, at: startTime, duration: 2000, on: destinationTrackID)
        node.name = file.name
        node.scriptFile = file
        completingPlacement { effects[node.id] = node }
        selectedNodeID = node.id
        effectsChanged()
        return node
    }

    /// Re-reads the first lines of every script file the document names.
    ///
    /// Bumps the revision only when something changed: writing an observed
    /// value redraws every card reading it, change or not.
    func refreshScriptSnippets() {
        guard let projectFolder else { return }

        let onDisk = (try? ScriptStore.files(inFolder: projectFolder)) ?? []
        let files = Set(effects.nodes.compactMap(\.scriptFile)).union(onDisk)
        var snippets: [String: [String]] = [:]
        var missing: Set<String> = []
        for file in files {
            guard let source = try? ScriptStore.read(file, inFolder: projectFolder) else {
                missing.insert(file.name)
                continue
            }
            snippets[file.name] = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(Self.snippetLines)
                .map(String.init)
        }

        guard snippets != scriptSnippets || missing != missingScripts || onDisk != folderScripts
        else { return }
        scriptSnippets = snippets
        missingScripts = missing
        folderScripts = onDisk
        scriptsRevision &+= 1
    }

    /// How many lines a script card shows.
    private static let snippetLines = 5

    /// Renames a script file on disk and points every clip that ran it at the
    /// new name.
    ///
    /// **Not undoable, by design.** ⌘Z cannot rename the file back on disk,
    /// and undoing only the references would leave the document naming a file
    /// that no longer exists — the silent disagreement between document and
    /// disk the scripts move to files was meant to end. So the references are
    /// written outside the history, as `reloadScripts` does; the project is
    /// still marked unsaved, because the document changed.
    ///
    /// Every clip naming the file follows, **locked ones too**: a lock refuses
    /// edits to what a clip does, and leaving it pointing at a name that is
    /// gone would break it rather than protect it.
    ///
    /// - Returns: whether the rename happened. On failure `saveError` says
    ///   why, and nothing on disk or in the document has changed.
    @discardableResult
    public func renameScript(_ file: ScriptFile, to proposed: String) -> Bool {
        guard let projectFolder else { return false }

        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = ScriptFile(name: trimmed) else {
            saveError = "“\(trimmed)” can't be a script name."
            return false
        }
        guard target != file else { return true }

        let destination = ScriptStore.url(of: target, inFolder: projectFolder)
        // Never over another file: a rename that silently replaced a script
        // would lose its code with no undo to get it back.
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            saveError = "A script named \(target.fileName) already exists."
            return false
        }
        do {
            try FileManager.default.moveItem(
                at: ScriptStore.url(of: file, inFolder: projectFolder),
                to: destination,
            )
        } catch {
            saveError = "Could not rename \(file.fileName)."
            return false
        }

        withoutRecording {
            for node in effects.nodes where node.scriptFile == file {
                var renamed = node
                renamed.scriptFile = target
                effects[node.id] = renamed
            }
        }
        saveError = nil
        refreshScriptSnippets()
        // Every clip naming the file, so an edit that names none: their code
        // resolves through the new name from the next pass on.
        effectsChanged()
        return true
    }

    /// Whether this clip has a script file that exists to be opened.
    ///
    /// Both halves matter. Offering the action on a clip that is not a script
    /// is a menu item that cannot work, and handing a **missing** path to an
    /// editor opens an empty untitled window — which reads as the script
    /// having been lost rather than as a file that is not there.
    public func canOpenScript(_ nodeID: EffectNode.ID) -> Bool {
        guard let file = effects[nodeID]?.scriptFile else { return false }
        return scriptURL(for: file) != nil
    }

    /// Opens a clip's script in an external editor.
    ///
    /// Two clips sharing a file open the same file, which is the point of
    /// sharing: whichever clip you reach for, you are editing the one script.
    public func openScriptExternally(_ nodeID: EffectNode.ID) {
        guard let file = effects[nodeID]?.scriptFile else { return }
        openScriptExternally(file: file)
    }

    /// Opens a script file by name — the card of a file no clip runs has no
    /// clip to go through.
    public func openScriptExternally(file: ScriptFile) {
        guard let url = scriptURL(for: file) else { return }
        guard openScriptHandler?(url) == true else {
            // A click that silently does nothing is worse than one that
            // fails: the author cannot tell the app from their setup.
            saveError = "Could not open \(url.lastPathComponent) in an editor."
            return
        }
        saveError = nil
    }

    /// Where a script lives, when it is on disk.
    private func scriptURL(for file: ScriptFile) -> URL? {
        guard let projectFolder else { return nil }

        let url = ScriptStore.url(of: file, inFolder: projectFolder)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }


    /// Where the selected clip's pixels are, as the canvas last measured them.
    ///
    /// Supplied by the app rather than worked out here, for the same reason the
    /// preview and the export are: the box comes from the renderer, and a
    /// feature cannot import another. Measured rather than computed because a
    /// clip's transform holds where its *pivot* is, and for anything but a
    /// centred sprite that is a different number from where its pixels land.
    public var selectionBounds: (() -> ClipBounds?)?

    /// Brings image files into the beatmap folder, returning their new
    /// relative paths.
    ///
    /// Supplied by the app: copying a file is the folder's business, and a
    /// feature cannot import another. Returns the paths rather than reloading
    /// on its own so the panel can select what just arrived.
    public var importAssets: ((AssetDestination) -> [String])?

    /// Whether importing is possible — there has to be a folder to copy into.
    public var canImportAssets: Bool { importAssets != nil }

    /// Copies files chosen by the author into the project, and lists them.
    ///
    /// Copied rather than referenced, because osu! reads only what sits in the
    /// beatmap folder: an asset linked from elsewhere works in the editor and
    /// arrives broken in the game — the worst kind of failure, since it looks
    /// finished right up until it ships.
    public func importAssetsFromDisk(into destination: AssetDestination) {
        guard let importAssets else { return }
        let returned = importAssets(destination)
        // Said, not silently dropped: a file the panel cannot hold would
        // otherwise copy into the folder and never show up.
        let added = returned.filter(AssetItem.Kind.isSupported)
        if added.count != returned.count {
            saveError = "Some files were skipped: only png, jpg, wav, mp3 and ogg can be imported."
        }
        guard !added.isEmpty else { return }

        // Merged rather than replacing: the folder listing was taken when the
        // project opened, and re-walking the whole folder to learn about two
        // files is work for an answer already in hand.
        let merged = Set(folderPaths).union(added)
        folderPaths = merged.sorted()
        rebuildAssets(missing: missingPaths)
    }

    /// A thumbnail for a file in the beatmap folder.
    ///
    /// Supplied by the app for the same reason the preview and the export are:
    /// reading an image is the renderer's business, and a feature cannot import
    /// another. A panel that lists filenames makes you open each one to find
    /// out what it is — the picture *is* the label.
    public var assetThumbnail: ((String) -> CGImage?)?

    /// Thumbnails already loaded, by path.
    ///
    /// Cached because a grid asks for every visible one on every rebuild, and
    /// decoding a PNG per row per frame is the same mistake as evaluating an
    /// effect in a `body`. `nil` inside the dictionary is a remembered failure:
    /// a file that could not be read must not be retried sixty times a second.
    @ObservationIgnored private var thumbnails: [String: CGImage?] = [:]

    /// The thumbnail for a path, loading it once.
    public func thumbnail(for path: String) -> CGImage? {
        if let cached = thumbnails[path] { return cached }
        // A sound has no picture to decode; asking would only cache a failure.
        guard AssetItem.Kind.inferred(from: path) == .image else { return nil }
        let image = assetThumbnail?(path)
        thumbnails[path] = image
        return image
    }

    /// Where the last export landed, so the UI can offer to reveal it.
    public private(set) var lastExport: URL?

    /// Why the last export failed, if it did.
    public private(set) var exportError: String?

    public var canExport: Bool { projectFolder != nil && exportHandler != nil }

    // ─── Video ───────────────────────────────────────────────────────────────

    /// Renders the storyboard to a video file, if someone has wired up how.
    ///
    /// Supplied by the app for the same reason the storyboard export is: the
    /// renderer belongs to another feature, and features do not import each
    /// other.
    @ObservationIgnored
    public var videoExportHandler: ((URL, @escaping @Sendable (Double) -> Void) async throws -> Void)?

    /// How far a running video export has got, or `nil` when none is running.
    public private(set) var videoProgress: Double?

    /// Why the last video export failed, if it did.
    public private(set) var videoError: String?

    public var canExportVideo: Bool { videoExportHandler != nil && videoProgress == nil }

    /// The stretch a video needs to cover: from the first sprite to the last.
    ///
    /// Not the song. A storyboard often occupies a fraction of the track, and
    /// rendering the silence around it is minutes of work producing black
    /// frames — a five-minute song is nineteen thousand of them.
    public var videoRange: ClosedRange<Double>? {
        let sprites = evaluated
        guard !sprites.isEmpty else { return nil }

        var lower = Double.greatestFiniteMagnitude
        var upper = -Double.greatestFiniteMagnitude
        for sprite in sprites {
            for command in sprite.commands {
                lower = Swift.min(lower, command.startTime)
                upper = Swift.max(upper, command.endTime)
            }
            for loop in sprite.loops {
                lower = Swift.min(lower, loop.startTime)
                for command in loop.commands {
                    upper = Swift.max(upper, loop.startTime
                        + command.endTime * Double(loop.loopCount))
                }
            }
        }

        guard upper > lower else { return nil }
        // A moment either side, so the first frame is not already mid-fade.
        return Swift.max(0, lower - 500)...(upper + 500)
    }

    public func exportVideo(to url: URL) {
        // The same reason: a video is the output, not the preview.
        guard let videoExportHandler, videoProgress == nil else { return }
        videoProgress = 0
        videoError = nil

        Task { @MainActor [self] in
            do {
                try await videoExportHandler(url) { [weak self] fraction in
                    Task { @MainActor in self?.videoProgress = fraction }
                }
                videoProgress = nil
            } catch {
                videoError = String(describing: error)
                videoProgress = nil
            }
        }
    }

    @discardableResult
    public func exportStoryboard() async -> Bool {
        // Wait for any pending pass, because here the sprites are the output
        // rather than the picture: mid-pass this would write what was on screen
        // a moment ago.
        await awaitEvaluation()
        return exportStoryboardNow()
    }

    private func exportStoryboardNow() -> Bool {
        guard let projectFolder, let exportHandler else { return false }
        do {
            // The same sprites the canvas is drawing, not a fresh evaluation:
            // what was on screen is what should be in the file, and evaluating
            // again is a second chance to disagree.
            lastExport = try exportHandler(evaluated, effects.samples, projectFolder)
            exportError = nil
            return true
        } catch {
            exportError = String(describing: error)
            lastExport = nil
            return false
        }
    }

    /// Where the playhead is, in project time.
    ///
    /// Kept here because the keyboard shortcuts need it and a `View`'s stored
    /// `currentTime` is captured when its body runs — the shortcut buttons live
    /// in a `.background` that SwiftUI has no reason to rebuild as the clock
    /// moves, so a paste landed at whatever time the editor opened at. Written
    /// each frame by whoever owns playback.
    @ObservationIgnored public var playheadTime: Double = 0 {
        didSet { observedPlayheadTime = playheadTime }
    }

    /// The same value, observed.
    ///
    /// Two properties rather than one because they answer opposite needs: the
    /// playhead marker *must* redraw with the clock, and the inspector must
    /// not. A single observed property would drag every reader along; a single
    /// ignored one would leave the marker frozen.
    public private(set) var observedPlayheadTime: Double = 0

    /// The clip that was copied, if any.
    ///
    /// Kept in the model rather than the system pasteboard: a clip is a value
    /// only this app understands, and putting it on the system board would put
    /// it in front of every other app for no one's benefit.
    public private(set) var copiedNode: EffectNode?

    public func copySelectedEffect() {
        guard let node = selectedEffect else { return }
        copiedNode = node
    }

    /// Pastes the copied clip onto a track, at a time.
    ///
    /// Onto the selected lane at the playhead by default, which is where a
    /// paste goes in any editor: where you are looking.
    @discardableResult
    public func pasteEffect(
        at time: Double,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode? {
        guard let source = copiedNode,
              // From the copied node, not its type: what a paste should carry
              // is whatever that clip declared, and for an effect whose
              // controls come from stored state the type cannot say.
              let descriptor = library.descriptor(for: source)
        else { return nil }

        var node = effects.add(
            descriptor,
            at: max(0, time),
            duration: source.duration,
            on: trackID ?? destinationTrackID,
        )
        node.name = source.name
        node.values = source.values
        node.transform = source.transform
        // And its filters, reidentified: the id prefixes the sprites a filter
        // derives, so two nodes sharing it would name the same ones.
        node.filters = source.filters.map { $0.reidentified() }
        // A fresh seed, for the same reason a duplicate gets one: the same
        // field drawn twice is not a second effect.
        node.seed = source.seed &+ 0x9E37_79B9
        // And its layers, re-homed under the new id for the same reason the
        // filters were reidentified.
        node.layers = source.layersRehomed(under: node.id, seed: node.seed)
        // And its code, with the controls it declares: a paste that drops the
        // script pastes an empty clip that reads as broken.
        node.scriptSource = source.scriptSource
        node.scriptFile = source.scriptFile
        node.scriptParameters = source.scriptParameters
        completingPlacement { effects[node.id] = node }

        selectedNodeID = node.id
        effectsChanged()
        return node
    }

    /// Deletes whatever is selected — a clip if one is, otherwise its lane.
    public func deleteSelection() {
        // Most specific first.
        //
        // A selected keyframe used to be invisible here, so pressing Delete
        // while working on one destroyed the whole clip it belonged to — and
        // there is no undo to take that back. What is selected is what gets
        // deleted, and a keyframe is a narrower selection than the clip that
        // holds it.
        if let selection = selectedKeyframe {
            removeKeyframe(
                selection.keyframeID,
                from: selection.property,
                on: selection.nodeID,
            )
            return
        }

        // A filter's key is just as narrow a selection, and was just as
        // invisible here — the same bug one kind of keyframe later. Every
        // selection this method can see has to be listed, or Delete quietly
        // reaches past it for something bigger.
        if let selection = selectedFilterKeyframe {
            removeFilterKeyframe(
                selection.keyframeID,
                for: selection.parameter,
                on: selection.filterID,
                in: selection.nodeID,
            )
            return
        }

        // The camera's keys, which belong to no clip — and the third kind of
        // key this method has had to be told about.
        if let selection = selectedCameraKeyframe {
            removeCameraKeyframe(selection.keyframeID, from: selection.property)
            return
        }

        // Editing the camera, nothing on the timeline is a clip or a lane:
        // Delete with no camera key selected is not aimed at whatever was
        // selected before the mode opened.
        guard !isEditingCamera else { return }

        // In keyframe mode the clip is selected only because its keys are being
        // edited. Deleting it from under that is never what the key was aimed
        // at, so it takes leaving the mode first.
        guard keyframeNodeID == nil else { return }

        if selectedNodeIDs.count > 1 {
            removeEffects(selectedNodeIDs)
        } else if let nodeID = selectedNodeID {
            removeEffect(nodeID)
        } else if let trackID = selectedTrackID {
            requestRemoveTrack(trackID)
        }
    }

    /// Copies an effect, selecting the copy.
    ///
    /// Selecting it is the point: a duplicate is made to be changed, and having
    /// to hunt for which of two identical clips is the new one is friction in
    /// the way of that.
    @discardableResult
    public func duplicateEffect(_ nodeID: EffectNode.ID) -> EffectNode? {
        let copy = effects.duplicate(nodeID)
        if let copy { selectedNodeID = copy.id }
        effectsChanged(node: nodeID)
        return copy
    }

    public func removeEffect(_ nodeID: EffectNode.ID) {
        effects.remove(nodeID)
        pruneSelection()
        effectsChanged(node: nodeID)
    }

    /// Removes several clips as one edit, so one undo brings them all back.
    ///
    /// Written to a copy and assigned once: undo snapshots on every write to
    /// `effects`, and a loop of removes would be a loop of undo steps.
    public func removeEffects(_ nodeIDs: Set<EffectNode.ID>) {
        var document = effects
        for node in effects.nodes where nodeIDs.contains(node.id) {
            document.remove(node.id)
        }
        effects = document
        pruneSelection()
        effectsChanged()
    }

    /// Duplicates every selected clip, selecting the copies — the same promise
    /// a single duplicate makes, kept for a group.
    public func duplicateSelection() {
        guard selectedNodeIDs.count > 1 else {
            if let selectedNodeID { duplicateEffect(selectedNodeID) }
            return
        }
        var document = effects
        let copies = selectedNodesInOrder.compactMap { document.duplicate($0.id) }
        effects = document
        select(group: Set(copies.map(\.id)))
        effectsChanged()
    }

    /// Shifts every selected clip along the timeline by the same amount.
    ///
    /// Clamped as a group: the earliest clip stops at zero and the rest keep
    /// their distance from it. Clamping each on its own would squash the group
    /// together, and the spacing is the point of moving them as one. Locked
    /// clips stay where they are, as they do for a single drag.
    public func moveSelection(by delta: Double) {
        let movable = selectedNodesInOrder.filter { !isLocked($0.id) }
        guard let earliest = movable.map(\.startTime).min() else { return }
        let shift = max(delta, -earliest)
        guard shift != 0 else { return }

        var document = effects
        for node in movable {
            document.move(node.id, to: node.startTime + shift)
        }
        effects = document
        effectsChanged()
    }

    /// How far a group dragged on the timeline may go before its earliest clip
    /// would cross zero — what the lane previews with, so the drag never shows
    /// a place the commit will not honour.
    public func clampedSelectionShift(_ delta: Double) -> Double {
        let earliest = selectedNodesInOrder.filter { !isLocked($0.id) }.map(\.startTime).min() ?? 0
        return max(delta, -earliest)
    }

    public func setValue(_ value: EffectValue, for parameterID: String, on nodeID: EffectNode.ID) {
        effects.setValue(value, for: parameterID, on: nodeID)
        effectsChanged(node: nodeID)
    }

    /// The selected clip, if it is a script — otherwise `nil`.
    ///
    /// What the side panel asks before offering an editor. A clip's type is the
    /// only thing that decides, and asking here keeps the view from knowing the
    /// type string.
    public var selectedScriptID: EffectNode.ID? {
        guard let nodeID = selectedNodeID,
              effects[nodeID]?.type == ScriptEffect.descriptor.type
        else { return nil }
        return nodeID
    }

    /// What ⌘S should do while a script is being edited.
    ///
    /// Set by the editor panel and cleared when it goes away, so the shell's
    /// own ⌘S can hand over rather than swallow the key.
    ///
    /// A closure rather than two buttons both claiming the shortcut: that was
    /// the bug — the shell's button won, saw a text field had focus, and
    /// returned without doing anything, so the editor's button never ran and
    /// the footer sat on "⌘S to run" while nothing ran. One shortcut, one
    /// owner, and the owner asks whoever is in front of it.
    @ObservationIgnored public var runScriptHandler: (() -> Void)?

    /// Takes on whatever controls the scripts declared in the pass that landed.
    ///
    /// Applied here rather than from inside `evaluate`, which would mutate the
    /// document during an evaluation of that document — and would land on the
    /// wrong actor besides.
    ///
    /// Written through `effects` so `EditHistory` sees it, and only when a
    /// declaration actually changed: a `params()` call returning the same list
    /// on every keystroke would spend an undo entry per character typed.
    private func adoptScriptDeclarations() {
        for node in effects.nodes where node.type == ScriptEffect.descriptor.type {
            guard let declared = ScriptRuntime.report(for: node.id)?.declared,
                  declared != node.scriptParameters
            else { continue }

            var updated = node
            updated.scriptParameters = declared
            effects[node.id] = updated
        }
    }

    /// What a script node's last run reported.
    ///
    /// A closure rather than a stored dictionary, because the ledger it reads
    /// lives in Core and is written by the evaluation pass — a copy here would
    /// be a second place for the same facts, kept in step by hand.
    @ObservationIgnored public var scriptReport: ((EffectNode.ID) -> ScriptRuntime.Report?)?



    /// Sets a parameter on one layer of a compound effect.
    public func setLayerValue(
        _ value: EffectValue,
        for parameterID: String,
        onLayer layerID: EffectNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        effects.setValue(value, for: parameterID, onLayer: layerID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    public func toggleLayerVisibility(_ layerID: EffectNode.ID, in nodeID: EffectNode.ID) {
        effects.toggleLayerVisibility(layerID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    public func moveEffect(_ nodeID: EffectNode.ID, to startTime: Double) {
        effects.move(nodeID, to: startTime)
        effectsChanged(node: nodeID)
    }

    public func moveEffect(_ nodeID: EffectNode.ID, toTrack trackID: EffectTrack.ID) {
        effects.move(nodeID, toTrack: trackID)
        effectsChanged()
    }

    public func resizeEffect(_ nodeID: EffectNode.ID, startTime: Double, duration: Double) {
        // In the model so every path obeys, not just the view that draws no
        // ears: a sound's length is its file's, and stretching it would
        // promise something the game does not do.
        if let node = effects[nodeID],
           library.descriptor(for: node)?.isResizable == false { return }
        effects.resize(nodeID, startTime: startTime, duration: duration)
        effectsChanged(node: nodeID)
    }

    // ─── Keyframes ───────────────────────────────────────────────────────────

    public func setKeyframe(
        _ value: Double,
        for property: TransformProperty,
        at time: Double,
        easing: Easing = .linear,
        on nodeID: EffectNode.ID,
    ) {
        effects.setKeyframe(value, for: property, at: time, easing: easing, on: nodeID)
        effectsChanged(node: nodeID)
    }

    public func removeKeyframe(
        _ keyframeID: Keyframe.ID,
        from property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        effects.removeKeyframe(keyframeID, from: property, on: nodeID)
        if selectedKeyframe?.keyframeID == keyframeID { selectedKeyframe = nil }
        effectsChanged(node: nodeID)
    }

    /// Changes a selected key's value, keeping it where it is in time.
    public func setKeyframeValue(
        _ value: Double,
        for keyframeID: Keyframe.ID,
        in property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        guard let node = effects[nodeID],
              let key = node.transform[property].keyframes.first(where: { $0.id == keyframeID })
        else { return }
        effects.setKeyframe(value, for: property, at: key.time, easing: key.easing, on: nodeID)
        effectsChanged(node: nodeID)
    }

    public func moveKeyframe(
        _ keyframeID: Keyframe.ID,
        in property: TransformProperty,
        to time: Double,
        on nodeID: EffectNode.ID,
    ) {
        effects.moveKeyframe(keyframeID, in: property, to: time, on: nodeID)
        effectsChanged(node: nodeID)
    }

    public func setKeyframeEasing(
        _ easing: Easing,
        for keyframeID: Keyframe.ID,
        in property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        effects.setKeyframeEasing(easing, for: keyframeID, in: property, on: nodeID)
        effectsChanged(node: nodeID)
    }

    /// Sets a property's resting value.
    ///
    /// What editing a field does when the property is *not* animated. With
    /// animation on, the field lays a keyframe instead — which is the whole
    /// distinction, and collapsing the two planted keys nobody asked for every
    /// time the playhead moved.
    public func setTransformValue(
        _ value: Double,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        effects.setTransformValue(value, for: property, on: nodeID)
        effectsChanged(node: nodeID)
    }

    /// The transform values a canvas drag started from.
    ///
    /// Held here rather than in the view: a gesture spans many events, and a
    /// `@State` tuple in a `View` struct does not survive between them — so
    /// every frame re-read the value it had just written, compounding each step
    /// until moving cancelled itself out and scaling ran away backwards.
    /// **It carries the node it belongs to.**
    ///
    /// Without that, a gesture that ends without a finished event — or simply a
    /// different clip selected next — leaves the previous clip's position
    /// cached, and the next drag measures from there. Logged on a duplicated
    /// shape sitting at x 720: the baseline came back as −108, the original's
    /// position, so the copy jumped somewhere neither the hand nor the
    /// inspector had asked for.
    @ObservationIgnored private var canvasDragOrigin: (
        node: EffectNode.ID, x: Double, y: Double, scaleX: Double, scaleY: Double, rotation: Double
    )?

    /// Records where a canvas drag began, once per gesture.
    /// Where the selected clip sits, in stage units, or `nil` when nothing is
    /// selected.
    ///
    /// The grip on the canvas is drawn here rather than at the centre of the
    /// selection box, because for anything that travels the two are different
    /// places. A radial burst is the clearest case: it is emitted from one
    /// point and its box is the whole spray, several times the width of the
    /// stage and centred nowhere near the emitter — so a grip at the box
    /// centre sat away from the convergence the eye is looking at, and moving
    /// the clip appeared to send it somewhere unrelated.
    ///
    /// `@ObservationIgnored` on purpose: this is asked for at draw time by the
    /// canvas, and reading it in a `body` up the tree rebuilds the window on
    /// every playhead tick.
    /// Whether the selected clip refuses to be moved.
    ///
    /// `@ObservationIgnored` for the same reason `clipOrigin` is: it is asked
    /// for at draw time, and reading it in a `body` up the tree rebuilds the
    /// window on every playhead tick.
    @ObservationIgnored
    public var isSelectionLocked: Bool {
        // A group is locked only when every clip in it is: one that can still
        // move is a group the frame should let the hand drag.
        guard !selectedNodeIDs.isEmpty else { return false }
        return selectedNodeIDs.allSatisfy(isLocked)
    }

    /// Where the selected clip's position is drawn on the canvas.
    ///
    /// Through the storyboard camera, because that is what the canvas shows
    /// and what the selection box is measured on. Read straight off the
    /// transform, the grip sat beside the clip on any project with a camera —
    /// reported on one that rolls and zooms, with lanes at depth.
    @ObservationIgnored
    public var clipOrigin: (x: Double, y: Double)? {
        // A group has no single position to mark, so the canvas falls back to
        // the centre of the box around all of it — the pivot a group drag
        // turns and scales about.
        guard selectedNodeIDs.count <= 1,
              let nodeID = selectedNodeID, let node = effects[nodeID] else { return nil }
        let local = min(max(0, playheadTime - node.startTime), node.duration)
        let x = node.transform.value(.x, at: local)
        let y = node.transform.value(.y, at: local)
        guard let z = canvasCameraDepth(of: nodeID) else { return (x, y) }
        return CameraTransform.project(x, y, through: effects.camera, at: playheadTime, z: z)
    }

    /// The depth the canvas sees a clip's lane at through the camera, or `nil`
    /// when it draws the lane as stored.
    ///
    /// The same condition `canvasSprites` decides the picture by: while the
    /// camera is edited the canvas shows the world before it, and a lane fixed
    /// to the screen never follows it.
    private func canvasCameraDepth(of nodeID: EffectNode.ID) -> Double? {
        guard !(isEditingCamera && !isViewingThroughCamera),
              let trackID = effects.trackID(of: nodeID),
              let track = effects.tracks.first(where: { $0.id == trackID }),
              track.followsCamera
        else { return nil }
        return track.z
    }

    private func canvasDragBaseline(for node: EffectNode, at time: Double) -> (
        x: Double, y: Double, scaleX: Double, scaleY: Double, rotation: Double
    ) {
        // Only this node's. A baseline belonging to another clip is worse than
        // none: it measures the drag from a place the clip has never been.
        if let canvasDragOrigin, canvasDragOrigin.node == node.id {
            return (
                x: canvasDragOrigin.x, y: canvasDragOrigin.y,
                scaleX: canvasDragOrigin.scaleX, scaleY: canvasDragOrigin.scaleY,
                rotation: canvasDragOrigin.rotation
            )
        }
        let local = min(max(0, time - node.startTime), node.duration)
        let origin = (
            x: node.transform.value(.x, at: local),
            y: node.transform.value(.y, at: local),
            scaleX: node.transform.value(.scaleX, at: local),
            scaleY: node.transform.value(.scaleY, at: local),
            rotation: node.transform.value(.rotation, at: local)
        )
        canvasDragOrigin = (
            node: node.id,
            x: origin.x, y: origin.y, scaleX: origin.scaleX, scaleY: origin.scaleY,
            rotation: origin.rotation
        )
        return origin
    }

    /// Applies a drag from the canvas to the selected clip.
    ///
    /// Deltas are measured against the values the gesture started from, never
    /// the current ones: reading back what the last frame wrote compounds every
    /// step.
    /// Sends the selected clip to a stage landmark.
    ///
    /// The same landmarks a drag snaps to, reached by asking rather than by
    /// aiming: snapping helps once a hand is already close, and this is for
    /// "put it in the middle", which is a thing to state.
    ///
    /// Written as a nudge on top of the clip's current position, because the
    /// transform holds where the pivot is while the box says where the pixels
    /// are — assigning the landmark straight to the position would centre the
    /// pivot instead of the picture.
    ///
    /// A group aligns as one: the box is the one around all of it, and every
    /// clip takes the same nudge, so their arrangement survives.
    public func align(_ alignment: StageSnap.Alignment) {
        let movable = selectedNodesInOrder.filter { !isLocked($0.id) }
        guard !movable.isEmpty, let box = selectionBounds?() else { return }

        let offset = StageSnap.offset(
            toAlign: (minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY),
            alignment,
        )

        var document = effects
        for node in movable {
            if alignment.isHorizontal {
                document.setTransformValue(
                    node.transform[value: .x] + offset.dx, for: .x, on: node.id,
                )
            } else {
                document.setTransformValue(
                    node.transform[value: .y] + offset.dy, for: .y, on: node.id,
                )
            }
        }
        effects = document
        effectsChanged()
    }

    /// Whether there is a clip to align, and a measurement to align it by.
    public var canAlign: Bool {
        guard selectedNodeIDs.contains(where: { !isLocked($0) }) else { return false }
        return selectionBounds?() != nil
    }

    /// - Returns: whether the drag is one the document takes — `false` for no
    ///   selection or a locked clip, so the canvas knows no committed sprites
    ///   are coming to replace its preview.
    @discardableResult
    public func applyCanvasDrag(
        dx: Double,
        dy: Double,
        scaleX: Double,
        scaleY: Double,
        rotation: Double = 0,
        isStretch: Bool = false,
        isFinished: Bool,
        at time: Double,
    ) -> Bool {
        if selectedNodeIDs.count > 1 {
            return applyGroupCanvasDrag(
                dx: dx, dy: dy, scaleX: scaleX, scaleY: scaleY,
                rotation: rotation, isStretch: isStretch,
                isFinished: isFinished, at: time,
            )
        }

        guard let nodeID = selectedNodeID,
              let node = effects[nodeID],
              !isLocked(nodeID)
        else { return false }

        _ = canvasDragBaseline(for: node, at: time)

        // Nothing is written until the hand comes up.
        //
        // Every write re-evaluates the clip — thousands of sprites — and
        // re-uploads them to the GPU. Doing that per drag event meant the image
        // was always rebuilding from an edit already superseded by the next
        // one, so the picture lagged behind the pointer and the frame rate came
        // apart. This is the same bargain the timeline already makes when a
        // clip is dragged along its lane: preview locally, commit once.
        guard isFinished else { return true }

        let origin = canvasDragBaseline(for: node, at: time)
        var updated = node
        let local = min(max(0, time - node.startTime), node.duration)

        // The drag was measured on the picture, after the camera; the clip is
        // stored before it. Under a roll a drag to the right is a diagonal in
        // the lane, and under a zoom or at depth it is shorter or longer.
        var (dx, dy) = (dx, dy)
        if let z = canvasCameraDepth(of: nodeID) {
            (dx, dy) = CameraTransform.unproject(dx: dx, dy: dy, through: effects.camera, at: time, z: z)
        }

        if dx != 0 { write(origin.x + dx, for: .x, on: &updated, at: local) }
        if dy != 0 { write(origin.y + dy, for: .y, on: &updated, at: local) }
        // A corner keeps both axes together; a side stretches one on its own.
        //
        // The lock governs corners, not sides. Dragging a corner means "make
        // it bigger", so the pair moves together — but a side handle exists to
        // stretch one axis, and one that obeyed the lock was a second corner:
        // the frame showed one axis growing and the clip came out uniform, so
        // the preview promised something the commit would not honour.
        //
        // Which one it was is *passed*, never read off the values: a side
        // dragged back to exactly 1.0 looks like a corner from here.
        let stretching = isStretch
        let linkedX = !stretching && scaleIsLinked && scaleY != 1 ? scaleY : scaleX
        let linkedY = !stretching && scaleIsLinked && scaleX != 1 ? scaleX : scaleY

        if linkedX != 1 { write(origin.scaleX * linkedX, for: .scaleX, on: &updated, at: local) }
        if linkedY != 1 { write(origin.scaleY * linkedY, for: .scaleY, on: &updated, at: local) }
        // A turn needs no camera conversion: the camera's roll and zoom turn
        // and scale the whole lane, so an angle on screen is the same angle in
        // the lane.
        if rotation != 0 { write(origin.rotation + rotation, for: .rotation, on: &updated, at: local) }

        effects[nodeID] = updated
        effectsChanged()
        canvasDragOrigin = nil
        return true
    }

    /// Where each clip of a group stood when a canvas drag began, and the point
    /// the group turns and scales about.
    ///
    /// Captured on the first event for the same reason a single clip's
    /// baseline is: every event reports its total travel.
    @ObservationIgnored private var groupDragOrigin: (
        pivot: (x: Double, y: Double),
        nodes: [EffectNode.ID: (x: Double, y: Double, scaleX: Double, scaleY: Double, rotation: Double)]
    )?

    /// A canvas drag on a group: every clip moves, and a scale or a turn
    /// carries their positions about the group's centre.
    ///
    /// Scaled each about its own position, two clips grow into each other;
    /// about the centre they spread apart, which is what the frame around
    /// both — and the preview the canvas draws from the same pivot — showed
    /// while the hand was down.
    ///
    /// The geometry is done where the drag was measured, on the picture: each
    /// clip's position is taken through the camera, moved there, and the
    /// difference brought back into its lane. The same conversion a single
    /// clip's drag makes, applied per clip, since lanes can sit at different
    /// depths.
    private func applyGroupCanvasDrag(
        dx: Double,
        dy: Double,
        scaleX: Double,
        scaleY: Double,
        rotation: Double,
        isStretch: Bool,
        isFinished: Bool,
        at time: Double,
    ) -> Bool {
        let movable = selectedNodesInOrder.filter { !isLocked($0.id) }
        guard !movable.isEmpty else { return false }

        if groupDragOrigin == nil {
            var nodes: [EffectNode.ID: (x: Double, y: Double, scaleX: Double, scaleY: Double, rotation: Double)] = [:]
            for node in movable {
                let local = min(max(0, time - node.startTime), node.duration)
                nodes[node.id] = (
                    x: node.transform.value(.x, at: local),
                    y: node.transform.value(.y, at: local),
                    scaleX: node.transform.value(.scaleX, at: local),
                    scaleY: node.transform.value(.scaleY, at: local),
                    rotation: node.transform.value(.rotation, at: local)
                )
            }
            let box = selectionBounds?()
            groupDragOrigin = (
                pivot: box.map { (x: $0.centreX, y: $0.centreY) } ?? (x: 0, y: 0),
                nodes: nodes
            )
        }
        guard isFinished, let origin = groupDragOrigin else { return true }
        defer { groupDragOrigin = nil }

        let linkedX = !isStretch && scaleIsLinked && scaleY != 1 ? scaleY : scaleX
        let linkedY = !isStretch && scaleIsLinked && scaleX != 1 ? scaleX : scaleY
        let angle = rotation * .pi / 180
        let (c, s) = (cos(angle), sin(angle))
        let pivot = origin.pivot

        var document = effects
        for node in movable {
            guard let start = origin.nodes[node.id], var updated = document[node.id] else { continue }
            let local = min(max(0, time - node.startTime), node.duration)
            let depth = canvasCameraDepth(of: node.id)

            // On the picture: scale about the pivot, turn about it, shift —
            // the order `ClipPreview` draws in.
            let seen = depth.map {
                CameraTransform.project(start.x, start.y, through: effects.camera, at: time, z: $0)
            } ?? (start.x, start.y)
            let offsetX = (seen.0 - pivot.x) * linkedX
            let offsetY = (seen.1 - pivot.y) * linkedY
            var moveX = pivot.x + offsetX * c - offsetY * s + dx - seen.0
            var moveY = pivot.y + offsetX * s + offsetY * c + dy - seen.1
            if let depth {
                (moveX, moveY) = CameraTransform.unproject(
                    dx: moveX, dy: moveY, through: effects.camera, at: time, z: depth,
                )
            }

            if moveX != 0 { write(start.x + moveX, for: .x, on: &updated, at: local) }
            if moveY != 0 { write(start.y + moveY, for: .y, on: &updated, at: local) }
            if linkedX != 1 { write(start.scaleX * linkedX, for: .scaleX, on: &updated, at: local) }
            if linkedY != 1 { write(start.scaleY * linkedY, for: .scaleY, on: &updated, at: local) }
            if rotation != 0 { write(start.rotation + rotation, for: .rotation, on: &updated, at: local) }
            document[node.id] = updated
        }
        effects = document
        effectsChanged()
        return true
    }

    /// One transform write, following the same rule the inspector's fields do:
    /// a keyframe when the property animates, the resting value when it does
    /// not.
    private func write(
        _ value: Double,
        for property: TransformProperty,
        on node: inout EffectNode,
        at localTime: Double,
    ) {
        if node.transform[property].isActive {
            _ = node.transform[property].set(value, at: localTime)
        } else {
            node.transform[value: property] = value
        }
    }

    /// Whether the two scale axes move together.
    ///
    /// On by default: scaling uniformly is what "make it bigger" means, and
    /// stretching is the deliberate act. Kept on the model rather than in the
    /// inspector so it survives the panel being rebuilt, which happens on every
    /// frame the playhead moves.
    public var scaleIsLinked = true

    /// Writes one scale axis, and the other with it when they are linked.
    ///
    /// The same number in both, which is what the lock is for: keeping a clip
    /// square while it grows. Carrying a ratio instead sounds cleverer and is
    /// not what anyone asks of a lock — it also read the axis back *after*
    /// writing it, so the ratio came out of the value it had just set and one
    /// axis at 0.3 sent the other to 1.5.
    public func setScale(
        _ value: Double,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        at time: Double,
    ) {
        write(value, for: property, on: nodeID, at: time)
        guard scaleIsLinked else { return }
        write(value, for: property == .scaleX ? .scaleY : .scaleX, on: nodeID, at: time)
    }

    /// One transform write, following the inspector's own rule.
    private func write(
        _ value: Double,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        at time: Double,
    ) {
        guard let node = effects[nodeID] else { return }
        if node.transform[property].isEmpty {
            setTransformValue(value, for: property, on: nodeID)
        } else {
            setKeyframe(value, for: property, at: time, on: nodeID)
        }
    }

    /// Writes a transform property the way an edit from the canvas means it.
    ///
    /// The same rule the inspector's fields follow, and deliberately the one
    /// place both go through: with the property animated this plants a keyframe
    /// at the playhead, and without it this moves the resting value. Two paths
    /// to the same edit would eventually disagree about which one a drag meant.
    ///
    /// This is what makes dragging on the canvas honest — the box moves what
    /// the panel says it moves.
    public func setTransformValueFromCanvas(
        _ value: Double,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        at time: Double,
    ) {
        guard let node = effects[nodeID], !isLocked(nodeID) else { return }

        if node.transform[property].isActive {
            // Local to the clip, like every other keyframe time.
            let local = min(max(0, time - node.startTime), node.duration)
            setKeyframe(value, for: property, at: local, on: nodeID)
        } else {
            setTransformValue(value, for: property, on: nodeID)
        }
    }

    /// Whether a clip cannot be edited, because its lane is locked.
    public func isLocked(_ nodeID: EffectNode.ID) -> Bool {
        guard let trackID = effects.trackID(of: nodeID) else { return false }
        return effects.track(id: trackID)?.isLocked ?? false
    }

    /// Switches a property's animation on or off, keeping its keys.
    public func setAnimationEnabled(
        _ isEnabled: Bool,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        keeping time: Double = 0,
    ) {
        effects.setAnimationEnabled(isEnabled, for: property, on: nodeID, keeping: time)
        effectsChanged(node: nodeID)
    }

    public func clearKeyframes(
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        keeping time: Double = 0,
    ) {
        effects.clearKeyframes(for: property, on: nodeID, keeping: time)
        effectsChanged(node: nodeID)
    }

    /// Starts animating a property, planting a key at the playhead.
    ///
    /// The first click on a stopwatch has to leave something behind, or nothing
    /// appears to have happened. The key holds the value the property already
    /// had, so switching animation on changes nothing on screen.
    public func beginAnimating(
        _ property: TransformProperty,
        on nodeID: EffectNode.ID,
        at localTime: Double,
    ) {
        guard let node = effects[nodeID] else { return }
        // The key holds the resting value, so switching animation on changes
        // nothing on screen — it only changes what editing the field will do.
        let current = node.transform.value(property, at: localTime)
        effects.setKeyframe(current, for: property, at: localTime, on: nodeID)
        effectsChanged()
    }

    // ─── Camera ──────────────────────────────────────────────────────────────

    /// The storyboard camera. Keyed in song time, one for the whole scene.
    public var camera: StoryboardCamera { effects.camera }

    /// Sets where the camera rests — what editing a field does while the
    /// property is not animated.
    public func setCameraValue(_ value: Double, for property: CameraProperty) {
        effects.camera[value: property] = min(max(value, property.range.lowerBound), property.range.upperBound)
        cameraChanged()
    }

    /// Plants a camera key at a song time, replacing any already there.
    public func setCameraKeyframe(
        _ value: Double,
        for property: CameraProperty,
        at time: Double,
        easing: Easing = .linear,
    ) {
        var track = effects.camera[property]
        track.set(min(max(value, property.range.lowerBound), property.range.upperBound), at: max(0, time), easing: easing)
        // Putting a key down is asking for animation; leaving the track off
        // would make the click look like it did nothing.
        track.isEnabled = true
        effects.camera[property] = track
        cameraChanged()
    }

    public func removeCameraKeyframe(_ keyframeID: Keyframe.ID, from property: CameraProperty) {
        // A deleted key cannot stay selected: the inspector would go on
        // describing something that no longer exists.
        if selectedCameraKeyframe?.keyframeID == keyframeID { selectedCameraKeyframe = nil }
        var track = effects.camera[property]
        track.remove(keyframeID)
        effects.camera[property] = track
        cameraChanged()
    }

    public func moveCameraKeyframe(_ keyframeID: Keyframe.ID, in property: CameraProperty, to time: Double) {
        var track = effects.camera[property]
        track.move(keyframeID, to: time)
        effects.camera[property] = track
        cameraChanged()
    }

    public func setCameraKeyframeValue(_ value: Double, for keyframeID: Keyframe.ID, in property: CameraProperty) {
        var track = effects.camera[property]
        track.setValue(min(max(value, property.range.lowerBound), property.range.upperBound), for: keyframeID)
        effects.camera[property] = track
        cameraChanged()
    }

    public func setCameraKeyframeEasing(_ easing: Easing, for keyframeID: Keyframe.ID, in property: CameraProperty) {
        var track = effects.camera[property]
        track.setEasing(easing, for: keyframeID)
        effects.camera[property] = track
        cameraChanged()
    }

    /// Starts animating a camera property, holding what it showed at `time`
    /// so switching animation on changes nothing on screen.
    public func beginAnimatingCamera(_ property: CameraProperty, at time: Double) {
        setCameraKeyframe(camera.value(property, at: time), for: property, at: time)
    }

    /// Switches a camera property's animation on or off, keeping its keys —
    /// and, switching off, keeping where the camera was at `time` so the
    /// picture does not jump.
    public func setCameraAnimationEnabled(_ isEnabled: Bool, for property: CameraProperty, keeping time: Double) {
        var track = effects.camera[property]
        if !isEnabled, track.isActive {
            effects.camera[value: property] = track.value(at: time)
        }
        track.isEnabled = isEnabled
        effects.camera[property] = track
        cameraChanged()
    }

    /// Deletes a camera property's keys, keeping its value at `time`.
    public func clearCameraKeyframes(for property: CameraProperty, keeping time: Double) {
        if selectedCameraKeyframe?.property == property { selectedCameraKeyframe = nil }
        let held = camera.value(property, at: time)
        effects.camera[property] = KeyframeTrack()
        effects.camera[value: property] = held
        cameraChanged()
    }

    /// Applies a drag of the camera's frame on the canvas, in one edit.
    ///
    /// Auto-key, the way After Effects does it: a property with its stopwatch
    /// on gets a key at `time`, one without has its resting value moved. Only
    /// what the drag actually changed is written — a pan must not put down a
    /// zoom key nobody asked for, which would pin the zoom there for good.
    ///
    /// One edit for all three, so a drag is one undo step and one evaluation.
    public func applyCameraFrame(x: Double, y: Double, zoom: Double, rotation: Double? = nil, at time: Double) {
        var camera = effects.camera
        var changes: [(CameraProperty, Double)] = [(.x, x), (.y, y), (.zoom, zoom)]
        if let rotation { changes.append((.rotation, rotation)) }
        for (property, raw) in changes {
            let value = min(max(raw, property.range.lowerBound), property.range.upperBound)
            guard abs(value - camera.value(property, at: time)) > 1e-9 else { continue }

            var track = camera[property]
            if track.isActive {
                // The curve of a key already there is kept: `set` replaces the
                // key, and a drag is about where, not about how it travels.
                let easing = track.keyframes.first { abs($0.time - time) < 0.5 }?.easing ?? .linear
                track.set(value, at: max(0, time), easing: easing)
                camera[property] = track
            } else {
                camera[value: property] = value
            }
        }
        guard camera != effects.camera else { return }
        effects.camera = camera
        cameraChanged()
    }

    /// Moves the camera's position keys at one moment — dragging a point of
    /// its path on the canvas. The keys keep their times; only where the
    /// camera stands at that moment changes.
    public func moveCameraPathPoint(at time: Double, x: Double, y: Double) {
        var camera = effects.camera
        for (property, raw) in [(CameraProperty.x, x), (.y, y)] {
            var track = camera[property]
            guard let key = track.keyframes.first(where: { abs($0.time - time) < 0.5 }) else { continue }
            track.setValue(min(max(raw, property.range.lowerBound), property.range.upperBound), for: key.id)
            camera[property] = track
        }
        guard camera != effects.camera else { return }
        effects.camera = camera
        cameraChanged()
    }

    /// How far behind the focal plane a lane sits.
    public func setDepth(_ z: Double, on trackID: EffectTrack.ID) {
        guard let index = effects.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        effects.tracks[index].z = min(max(z, CameraProperty.z.range.lowerBound), CameraProperty.z.range.upperBound)
        cameraChanged()
    }

    /// Whether a lane follows the camera or stays fixed on screen.
    public func setFollowsCamera(_ follows: Bool, on trackID: EffectTrack.ID) {
        guard let index = effects.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        effects.tracks[index].followsCamera = follows
        cameraChanged()
    }

    // ─── Editing tracks ──────────────────────────────────────────────────────

    /// - Parameter index: where it lands in document order, or `nil` to put it
    ///   on top. Adding from a row's own menu is asking for a lane *beside that
    ///   one*, so the caller says where.
    @discardableResult
    public func addTrack(at index: Int? = nil) -> EffectTrack {
        let track = effects.addTrack(at: index)
        selectedTrackID = track.id
        selectedNodeID = nil
        effectsChanged()
        return track
    }

    /// The lane a delete is waiting on confirmation for, if any.
    ///
    /// Asking lives in the model rather than in the row that was right-clicked,
    /// because **two** paths delete a track — the menu and the Delete key — and
    /// a confirmation attached to one of them leaves the other destroying work
    /// in silence. That is the path most easily hit by accident.
    public var trackPendingDeletion: EffectTrack?

    /// How many clips would go with it, for the alert to say so.
    public var clipsPendingDeletion: Int {
        trackPendingDeletion?.nodes.count ?? 0
    }

    /// Deletes a lane, asking first when there is work on it.
    ///
    /// An empty lane goes without a word: confirming a delete that destroys
    /// nothing trains people to dismiss the dialog, and the one time it matters
    /// they will dismiss that one too. **There is no undo for this** — a track
    /// with clips is somebody's afternoon.
    public func requestRemoveTrack(_ trackID: EffectTrack.ID) {
        guard let track = effects.track(id: trackID) else { return }
        guard !track.nodes.isEmpty else {
            removeTrack(trackID)
            return
        }
        trackPendingDeletion = track
    }

    /// Goes through with the delete the alert was asking about.
    public func confirmRemoveTrack() {
        guard let track = trackPendingDeletion else { return }
        trackPendingDeletion = nil
        removeTrack(track.id)
    }

    public func cancelRemoveTrack() {
        trackPendingDeletion = nil
    }

    public func removeTrack(_ trackID: EffectTrack.ID) {
        effects.removeTrack(trackID)
        if selectedTrackID == trackID { selectedTrackID = effects.tracks.last?.id }
        // The selected effect may have gone with the lane it was on.
        pruneSelection()
        effectsChanged()
    }

    public func renameTrack(_ trackID: EffectTrack.ID, to name: String) {
        effects.rename(trackID, to: name)
        // A name is a label; no sprite carries it.
        appearanceChanged()
    }

    /// Renames one clip.
    ///
    /// `appearanceChanged()` rather than `effectsChanged()`, for the same
    /// reason the track above does: a name is a label and no sprite carries
    /// it. The distinction is not cosmetic here — the field commits per
    /// keystroke, and a script clip re-evaluated on every letter is 572
    /// sprites and 13,000 commands per character typed. It is the bug the
    /// track colour already had.
    public func renameEffect(_ nodeID: EffectNode.ID, to name: String) {
        effects.renameNode(nodeID, to: name)
        appearanceChanged()
    }

    // ─── Filters ─────────────────────────────────────────────────────────────

    /// The filters available to apply.
    public var filterDescriptors: [FilterDescriptor] {
        filters.descriptors
    }

    @discardableResult
    public func addFilter(_ descriptor: FilterDescriptor, to nodeID: EffectNode.ID) -> FilterNode? {
        let filter = effects.addFilter(descriptor, to: nodeID)

        // Applying a filter selects the clip it landed on, so its settings are
        // in front of whoever just dropped it.
        selectedNodeID = nodeID
        if let trackID = effects.trackID(of: nodeID) { selectedTrackID = trackID }

        effectsChanged(node: nodeID)
        return filter
    }

    public func removeFilter(_ filterID: FilterNode.ID, from nodeID: EffectNode.ID) {
        effects.removeFilter(filterID, from: nodeID)
        effectsChanged(node: nodeID)
    }

    public func toggleFilter(_ filterID: FilterNode.ID, in nodeID: EffectNode.ID) {
        effects.toggleFilter(filterID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    public func setFilterValue(
        _ value: EffectValue,
        for parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        effects.setFilterValue(value, for: parameterID, on: filterID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    /// What each filter group in the keyframe editor is showing.
    ///
    /// Three states, not two, and that is the whole reason this is a dictionary
    /// rather than a set of open ids: a filter somebody is animating opens on
    /// its own — they are exactly who wants to see its diamonds — so there has
    /// to be somewhere to record "shut it anyway". With only an open set, the
    /// chevron on an animated filter would appear to do nothing.
    ///
    /// It lives on the model rather than in the view because the timeline sizes
    /// itself from the row count, and a height that cannot see what is folded
    /// is a height that disagrees with what gets drawn.
    public var filterGroupState: [FilterNode.ID: Bool] = [:]

    /// Whether a filter's group is showing its properties.
    ///
    /// Unasked, a filter with keyframes is open and one without is shut: a clip
    /// carrying three untouched filters is three lines rather than fifteen rows
    /// above the nine anybody came for.
    public func isFilterGroupExpanded(_ filterID: FilterNode.ID, in nodeID: EffectNode.ID) -> Bool {
        if let asked = filterGroupState[filterID] { return asked }
        guard let filter = effects[nodeID]?.filters.first(where: { $0.id == filterID })
        else { return false }
        return filter.animations.values.contains { !$0.isEmpty }
    }

    public func toggleFilterGroup(_ filterID: FilterNode.ID, in nodeID: EffectNode.ID) {
        filterGroupState[filterID] = !isFilterGroupExpanded(filterID, in: nodeID)
    }

    /// Whether the transform group is showing its nine properties.
    ///
    /// Open by default, because it is what the mode is for.
    public var isTransformGroupExpanded = true

    /// Whether the camera's rows are open in its keyframe mode.
    ///
    /// On the model rather than the view for the reason the transform's is:
    /// the timeline is sized from its row count, and a height that cannot see
    /// what is folded is a height that disagrees with what is drawn.
    public var isCameraGroupExpanded = true

    // ─── Animating a filter's parameters ─────────────────────────────────────
    //
    // The same three moves the transform already has, because a stopwatch has
    // to mean the same thing wherever it appears. What differs is only that a
    // filter's parameters are named rather than a fixed list.

    /// The keyframes on one of a filter's parameters, if any.
    public func filterAnimation(
        _ parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
    ) -> KeyframeTrack? {
        effects[nodeID]?.filters.first { $0.id == filterID }?.animations[parameterID]
    }

    /// What a filter parameter is worth at a moment — its animation sampled
    /// there, or its resting value when nothing animates it.
    ///
    /// The inspector shows this in the field, so scrubbing the playhead over an
    /// animated parameter moves its number, exactly as the transform's does.
    public func filterValue(
        _ parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
        at localTime: Double,
    ) -> Double? {
        guard let filter = effects[nodeID]?.filters.first(where: { $0.id == filterID })
        else { return nil }

        if let track = filter.animations[parameterID], track.isActive {
            return track.value(at: localTime)
        }
        switch filter.values[parameterID] {
        case let .number(value): return value
        case let .integer(value): return Double(value)
        default: return nil
        }
    }

    /// Plants a key on a filter parameter, switching animation on if it was off.
    ///
    /// Adding a key to a disabled track re-enables it: planting a key is asking
    /// for the thing to animate, and leaving it inert would look like the click
    /// did nothing.
    public func setFilterKeyframe(
        _ value: Double,
        for parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
        at localTime: Double,
    ) {
        var track = filterAnimation(parameterID, on: filterID, in: nodeID) ?? KeyframeTrack()
        track.isEnabled = true
        track.set(value, at: localTime)
        effects.setFilterAnimation(track, for: parameterID, on: filterID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    /// Starts animating a filter parameter, planting a key at the playhead.
    ///
    /// The key holds the value the parameter already had, so switching
    /// animation on changes nothing on screen — it only changes what editing
    /// the field will do. The first click on a stopwatch still has to leave
    /// something behind, or nothing appears to have happened.
    public func beginAnimatingFilter(
        _ parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
        at localTime: Double,
    ) {
        guard let current = filterValue(
            parameterID, on: filterID, in: nodeID, at: localTime,
        ) else { return }
        setFilterKeyframe(
            current, for: parameterID, on: filterID, in: nodeID, at: localTime,
        )
    }

    /// Switches a filter parameter's animation on or off without discarding it.
    ///
    /// Keeps the value the animation held at that moment, the way the transform
    /// does: switching animation off is a decision about how a property
    /// behaves, not about what it is worth.
    public func setFilterAnimationEnabled(
        _ isEnabled: Bool,
        for parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
        at localTime: Double,
    ) {
        guard var track = filterAnimation(parameterID, on: filterID, in: nodeID) else { return }

        if !isEnabled, let held = filterValue(
            parameterID, on: filterID, in: nodeID, at: localTime,
        ) {
            // Written to the resting value before the track goes quiet, so the
            // parameter keeps looking the way it did a moment ago.
            effects.setFilterValue(
                .number(held), for: parameterID, on: filterID, in: nodeID,
            )
        }
        track.isEnabled = isEnabled
        effects.setFilterAnimation(track, for: parameterID, on: filterID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    /// Moves one of a filter parameter's keys along the timeline.
    public func moveFilterKeyframe(
        _ keyID: Keyframe.ID,
        for parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
        to localTime: Double,
    ) {
        guard var track = filterAnimation(parameterID, on: filterID, in: nodeID) else { return }
        track.move(keyID, to: localTime)
        effects.setFilterAnimation(track, for: parameterID, on: filterID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    /// Removes one key, leaving the rest of the animation alone.
    public func removeFilterKeyframe(
        _ keyID: Keyframe.ID,
        for parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        guard var track = filterAnimation(parameterID, on: filterID, in: nodeID) else { return }
        track.remove(keyID)
        if selectedFilterKeyframe?.keyframeID == keyID { selectedFilterKeyframe = nil }
        // An empty track is no animation, not an animation with nothing in it —
        // left behind, the row would linger with no keys on it. Dropped by
        // `EffectDocument.setFilterAnimation`, which is the one place that
        // decides it: guarding here too would be a second opinion waiting to
        // disagree.
        effects.setFilterAnimation(track, for: parameterID, on: filterID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    /// Changes what one of a filter parameter's keys is worth.
    public func setFilterKeyframeValue(
        _ value: Double,
        for keyID: Keyframe.ID,
        on parameterID: String,
        filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        guard var track = filterAnimation(parameterID, on: filterID, in: nodeID) else { return }
        track.setValue(value, for: keyID)
        effects.setFilterAnimation(track, for: parameterID, on: filterID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    /// Sets the curve a key travels away on.
    ///
    /// The easing belongs to the key it leaves *from*, which is how a storyboard
    /// command works — so this is the segment after `keyID`, not before it.
    public func setFilterKeyframeEasing(
        _ easing: Easing,
        for keyID: Keyframe.ID,
        on parameterID: String,
        filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        guard var track = filterAnimation(parameterID, on: filterID, in: nodeID) else { return }
        track.setEasing(easing, for: keyID)
        effects.setFilterAnimation(track, for: parameterID, on: filterID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    /// Throws away a filter parameter's keyframes, keeping what it was worth.
    ///
    /// Its own action rather than a side effect of the stopwatch, because there
    /// is no undo to climb out of it with.
    public func clearFilterAnimation(
        for parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
        keeping localTime: Double,
    ) {
        if let held = filterValue(parameterID, on: filterID, in: nodeID, at: localTime) {
            effects.setFilterValue(
                .number(held), for: parameterID, on: filterID, in: nodeID,
            )
        }
        if selectedFilterKeyframe?.filterID == filterID,
           selectedFilterKeyframe?.parameter == parameterID
        {
            selectedFilterKeyframe = nil
        }
        effects.setFilterAnimation(nil, for: parameterID, on: filterID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    /// How many sprites one effect produces.
    ///
    /// Evaluated rather than guessed: an emitter's count is a parameter, but a
    /// preset can cap it and a hidden node produces none.
    public func spriteCount(of node: EffectNode) -> Int {
        // Counted off the last completed pass, never evaluated here.
        //
        // The inspector reads this in its `body` to show what a clip costs, and
        // the cache is cleared by the edit that prompted the rebuild — so the
        // read landed on a miss and ran the whole effect *synchronously*.
        // Measured on an Audio Bars clip, that was **1,101 to 1,317ms of
        // frozen window** on every value typed into a field, and the freeze
        // came from a number shown as a hint.
        //
        // The async pass already produces these sprites. A count taken from it
        // is a moment out of date at worst, which is the right trade for a
        // readout that exists to warn about file size.
        evaluated.count { ClipBounds.sprite($0.id, belongsTo: node.id) }
    }

    /// How far past its own block a clip is still drawing, in milliseconds.
    ///
    /// Separate from `duration(of:on:)`, which reports repeats: a tail is the
    /// **same** pass still finishing, a repeat is another one starting. Drawn
    /// as one number, a clip whose particles outlive it grew a ghost for a
    /// repetition that never happens.
    /// How long one pass of a clip lasts, tail included.
    ///
    /// Handed to the timeline rather than left for it to divide out: the repeat
    /// ghosts used to infer the pass length from the total, which only works
    /// while a pass is exactly the clip. Once the tail joined the period that
    /// division started reporting a pass too many, at the wrong stride.
    public func passDuration(of nodeID: EffectNode.ID) -> Double {
        guard let node = effects[nodeID] else { return 0 }
        return node.duration + rawTail(of: node)
    }

    /// How many times a clip plays: once, plus whatever a loop adds.
    public func passCount(of nodeID: EffectNode.ID) -> Int {
        guard let node = effects[nodeID] else { return 1 }
        return node.loopRepeats
    }

    // ─── Motion path ─────────────────────────────────────────────────────────

    /// Whether the pen tool is armed.
    ///
    /// A mode rather than a permanent overlay: the path's points sit on top of
    /// the canvas and would swallow clicks meant for the clip underneath, and a
    /// tool that stays armed after it is finished is one that fights the app.
    public var isDrawingPath = false

    /// The path on the selected clip's Motion Path filter, if it has one.
    ///
    /// Nil when there is nothing to edit, which is what the canvas checks
    /// before drawing anything: an editor for a path that does not exist is an
    /// overlay intercepting clicks for no reason.
    public var editablePath: MotionPath? {
        guard let node = selectedEffect,
              let filter = node.filters.first(where: { $0.type == "path" && $0.isEnabled }),
              case let .path(path) = filter.values["path"]
        else { return nil }
        return path
    }

    /// Writes a path back to the selected clip.
    public func setEditablePath(_ path: MotionPath) {
        guard let node = selectedEffect,
              let filter = node.filters.first(where: { $0.type == "path" })
        else { return }
        setFilterValue(.path(path), for: "path", on: filter.id, in: node.id)
    }

    public func tail(of nodeID: EffectNode.ID) -> Double {
        // Read from the last completed pass, never computed here.
        //
        // The timeline asks for this per clip on every rebuild, and the edit
        // that prompts the rebuild invalidates it — so the read landed on a
        // miss and evaluated the whole effect *synchronously*. Measured on an
        // Audio Bars clip, **1,285ms of frozen window** on every value typed.
        //
        // The same bug as `spriteCount`, and the third time this pattern has
        // shown up: a cached answer whose cache is cleared by the very edit
        // that asks for it again is not a cache, it is a synchronous
        // evaluation with extra steps.
        tails[nodeID] ?? 0
    }

    /// How far one pass runs past the clip's own length.
    ///
    /// Measured on a single pass, before any loop multiplies it: a repeat
    /// restarts the whole thing, tail and all, so the overhang is a property of
    /// the pass rather than of the sequence.
    ///
    /// Read from the last completed pass, like `tail(of:)` — which measures
    /// exactly this, one pass before a loop multiplies it. It used to work it
    /// out here instead, and `duration(of:on:)` and `passDuration(of:)` both
    /// ask it for every clip on every timeline rebuild, right after the edit
    /// that cleared the answer: the clip was evaluated synchronously on the
    /// main thread. Invisible on a plain emitter; an AUDIO emitter decodes the
    /// song under its new position, and moving or resizing one froze the
    /// window for as long as that took.
    private func rawTail(of node: EffectNode) -> Double {
        tails[node.id] ?? 0
    }

    /// Answers the inspector asks every time it draws, kept until the effects
    /// change.
    ///
    /// Both of these run an effect in full — a 640-particle emitter under a
    /// ×4 loop costs about 12ms between them, and the inspector reads them from
    /// its `body`, which SwiftUI re-runs on every frame the playhead moves.
    /// Selecting such a clip dropped the whole editor to 24fps while nothing
    /// about it had changed. Neither answer can change without an edit, and an
    /// edit already bumps the revision.
    /// Not observed. These are written *during* a view's `body`, and observed
    /// state written while rendering invalidates the view that just read it —
    /// which redraws, writes again, and never settles. The app hung on load.
    /// A cache is not state anyone should redraw for: `effectsRevision` already
    /// says when the answers changed.
    @ObservationIgnored private var spriteCounts: [EffectNode.ID: Int] = [:]

    /// How badly each looped clip thins at its seams, from the last pass.
    /// Its own dictionary, like `tails`, rather than in the caches the
    /// revision clears: a result landing before the first read after an edit
    /// would be cleared by that very read.
    @ObservationIgnored private var seams: [EffectNode.ID: Double] = [:]

    /// How far each clip plays past its own length, from the last pass.
    @ObservationIgnored private var tails: [EffectNode.ID: Double] = [:]
    @ObservationIgnored private var cacheRevision = -1

    /// Drops both caches when the effects have moved on.
    ///
    /// Kept apart from the read below: clearing touches the same dictionaries
    /// that are held `inout` there, and Swift rejects the overlapping access
    /// outright rather than letting the two disagree.
    /// The span every placed clip covers, once its filters are counted.
    ///
    /// Cached, and that is the whole point. This is what the timeline draws
    /// against, so it is read from a dozen places in one rebuild — and each
    /// read walked every node asking ``duration(of:on:)`` about it, which
    /// looked each one up by a **linear search** through every track. Measured
    /// on a project of 84 nodes with `sample` on the running app: 720 calls a
    /// second costing **895 of every 1000 milliseconds**, while all of drawing
    /// used eight. The editor sat at 44fps with the GPU idle.
    ///
    /// Quadratic, so placing lyrics did not cause it — it took the project from
    /// 35 nodes to 84 and made it impossible to miss.
    public var playedTimeRange: ClosedRange<Double>? {
        invalidateCachesIfNeeded()
        if let cachedSpan { return cachedSpan.value }
        // Named `clipDuration` because a parameter called `duration` shadows
        // the method being called on the next line.
        let span = effects.timeRange { [self] trackID, clipDuration in
            duration(of: clipDuration, on: trackID)
        }
        cachedSpan = Box(value: span)
        return span
    }

    /// Wrapped, so "computed and nil" is distinct from "not computed".
    private struct Box {
        let value: ClosedRange<Double>?
    }

    @ObservationIgnored private var cachedSpan: Box?

    private func invalidateCachesIfNeeded() {
        guard cacheRevision != effectsRevision else { return }
        cacheRevision = effectsRevision
        // Always cleared in full: it is one value, and any edit can move it.
        cachedSpan = nil

        // Only the clip that changed, when the edit named one.
        //
        // These answers cost a full evaluation each, and the timeline asks for
        // one per clip on every rebuild — so clearing all of them meant a
        // keystroke re-evaluated every effect in the project *synchronously*,
        // on the main thread. Twenty clips is twenty emitters run over again to
        // redraw a row that did not change.
        //
        // The same bug this file already documents for `spriteCount`, made
        // again a level along: what is expensive here is not the caching, it is
        // deciding that everything is stale when one thing is.
        // The camera moves sprites, never adds or removes them.
        guard !onlyCameraMoved else { return }
        guard let edited = lastEditedNode else {
            spriteCounts.removeAll(keepingCapacity: true)
            return
        }

        spriteCounts[edited] = nil
    }

    private func cached<Value>(
        _ id: EffectNode.ID,
        in store: inout [EffectNode.ID: Value],
        make: () -> Value,
    ) -> Value {
        if let existing = store[id] { return existing }
        let made = make()
        store[id] = made
        return made
    }

    /// How badly a looped track thins at its seams, from 0 to 1.
    ///
    /// A loop's pass starts from an empty screen, so whatever was still alive
    /// at the end of the previous one is gone. Reported so a fire that flickers
    /// every few seconds has an explanation attached to it.
    public func loopSeamSeverity(for nodeID: EffectNode.ID) -> Double {
        guard let node = effects[nodeID],
              node.filters.contains(where: { $0.isEnabled && $0.type == LoopFilter.descriptor.type })
        else { return 0 }

        // Read from the last pass, never computed here: the inspector asks
        // from its `body`, and an audio clip under a loop would decode its song
        // on the main thread to answer.
        return seams[nodeID] ?? 0
    }

    /// How long a clip on this track actually runs, once its filters are
    /// applied.
    public func duration(of clipDuration: Double, on nodeID: EffectNode.ID) -> Double {
        guard let node = effects[nodeID] else { return clipDuration }

        // The tail first, then the filters.
        //
        // A loop's period is the longest command in its body — the clip **and
        // its tail** — so the next pass only starts once the previous one has
        // finished dying out. Multiplying the bare clip length instead reported
        // the repeats closer together than they actually play, which is what
        // put the ghosts out of step with the sound.
        //
        // Order matters: the tail belongs to one pass, so it goes in before the
        // count multiplies it. `tail(of:)` unwinds the same arithmetic to find
        // the overhang of the last pass, which is the only one that shows.
        let onePass = clipDuration + rawTail(of: node)
        return evaluator.duration(of: onePass, on: node)
    }

    /// How much a track's filters multiply its sprite count.
    ///
    /// Surfaced so a glow over a large emitter can be seen for what it is —
    /// a file osu! will not open — while it can still be turned down.
    public func spriteMultiplier(for nodeID: EffectNode.ID) -> Double {
        guard let node = effects[nodeID] else { return 1 }
        return evaluator.spriteMultiplier(for: node)
    }

    public func setColour(_ colour: TrackColour?, on trackID: EffectTrack.ID) {
        effects.setColour(colour, on: trackID)
        // Not `effectsChanged()`: a track's colour is a label in the editor and
        // reaches no sprite, so re-running every emitter for it is a second of
        // the main thread spent producing exactly what was already on screen.
        appearanceChanged()
    }

    /// Records a change that alters how the editor looks but not what it draws.
    ///
    /// The document still has to be saved and the views still have to redraw —
    /// what it skips is the evaluation, which is the expensive half.
    private func appearanceChanged() {
        effectsRevision &+= 1
        hasUnsavedChanges = true
    }

    public func setLayer(_ layer: Layer, on trackID: EffectTrack.ID) {
        effects.setLayer(layer, on: trackID)
        effectsChanged()
    }

    public func toggleVisibility(of trackID: EffectTrack.ID) {
        effects.toggleVisibility(of: trackID)
        effectsChanged()
    }

    public func toggleLock(of trackID: EffectTrack.ID) {
        effects.toggleLock(of: trackID)
        // A lock refuses edits; it changes nothing about what is drawn.
        appearanceChanged()
    }

    public func raiseTrack(_ trackID: EffectTrack.ID) {
        effects.raiseTrack(trackID)
        effectsChanged()
    }

    public func lowerTrack(_ trackID: EffectTrack.ID) {
        effects.lowerTrack(trackID)
        effectsChanged()
    }

    /// Moves a track to a position in one edit.
    ///
    /// A drag across six lanes used to be five `lowerTrack` calls, and each one
    /// re-evaluated the whole document to reach an arrangement nobody wanted to
    /// stop at. One move, one evaluation.
    public func moveTrack(_ trackID: EffectTrack.ID, toIndex index: Int) {
        effects.moveTrack(trackID, toIndex: index)
        effectsChanged()
    }

    /// Sends a track to the front or the back of the stack.
    ///
    /// The two ends are worth their own commands because they are where people
    /// actually want to go: "put this on top" is one thought, and stepping
    /// there one lane at a time is that thought spelled out five times.
    public func moveTrackToFront(_ trackID: EffectTrack.ID) {
        effects.moveTrack(trackID, toIndex: effects.tracks.count - 1)
        effectsChanged()
    }

    public func moveTrackToBack(_ trackID: EffectTrack.ID) {
        effects.moveTrack(trackID, toIndex: 0)
        effectsChanged()
    }

    /// Signals that something about the effects changed and re-evaluates.
    /// - Parameter node: which clip the edit touched, when it was only one.
    ///   Used so the "catching up" mark lands on that clip rather than on every
    ///   clip in the project — twenty spinners for one edit is both a lie and
    ///   twenty rows rebuilt to tell it.
    private func effectsChanged(node: EffectNode.ID? = nil) {
        effectsRevision &+= 1
        hasUnsavedChanges = true
        lastEditedNode = node
        onlyCameraMoved = false
        hasPendingClipEdit = true
        reevaluate()
    }

    /// Records an edit to the camera or to a lane's depth.
    ///
    /// Its own path because what it moves is only the last step of the
    /// pipeline: every clip's cached sprites are still right, so no entry is
    /// dropped and no tail is measured — the pass re-reads the cache and runs
    /// the camera over it. Sent through `effectsChanged()` instead, a nudged
    /// camera key would re-run every script in the project.
    private func cameraChanged() {
        effectsRevision &+= 1
        hasUnsavedChanges = true
        // Unless a clip edit is still waiting for the same pass: during a
        // gesture evaluation waits for the hand to settle, and a camera edit
        // landing in that pause must not wave through the clip edit before it
        // without its entry being dropped.
        if !hasPendingClipEdit { onlyCameraMoved = true }
        reevaluate()
    }

    /// Whether the edit waiting to be evaluated touched only the camera.
    @ObservationIgnored private var onlyCameraMoved = false

    /// Whether an edit that names clips is waiting for the next pass.
    @ObservationIgnored private var hasPendingClipEdit = false

    /// Rebuilds the sprites off the main thread.
    ///
    /// Evaluation used to run inline here, which is fine while it is fast and a
    /// frozen window the moment it is not: an emitter under a grid takes tens of
    /// milliseconds, and anything that reads the song takes far longer — a
    /// measured 1,176ms just to seek into an MP3. Every one of those was a
    /// stall someone felt as the app hanging.
    ///
    /// Last one wins. A slider dragged across its range starts an evaluation
    /// per step, and without cancelling the one for value 5 can land after the
    /// one for value 7 — the canvas would settle on a value the document no
    /// longer holds.
    ///
    /// The canvas keeps showing the last good sprites while a new pass runs,
    /// rather than emptying: a clip that blinks out while its numbers are being
    /// adjusted is worse than one a moment out of date, and `evaluatingNodes`
    /// says which clips are still catching up.
    /// Whether a continuous gesture is in flight, so evaluation can wait for a
    /// pause rather than chasing every step.
    @ObservationIgnored private var isGestureActive = false
    @ObservationIgnored private var pendingEvaluation: Task<Void, Never>?

    /// Rebuilds the sprites because something the effects *read* changed,
    /// rather than the document itself.
    ///
    /// An effect can depend on more than its own parameters — Audio Bars reads
    /// the song, Beat Pulse reads the tempo — and those arrive **after** the
    /// project opens. The first evaluation ran without them and its result was
    /// cached, so a bank of bars stayed on its placeholder wave until somebody
    /// happened to nudge a parameter. Nothing was wrong with the analysis; it
    /// was simply never asked again.
    public func inputsChanged() {
        effectsRevision &+= 1
        // Nothing here names a clip, and saying so matters: what moved is a
        // seam every effect reads, so the answer for *all* of them is stale.
        //
        // Left as it was, this inherited whatever the last edit had named, and
        // the pass would refresh one clip while the analyser it was waiting for
        // reached every one of them. Harmless while a pass measured everything
        // regardless; the moment work is skipped on the strength of this name,
        // it decides which clips keep drawing the wave they had before the song
        // had loaded.
        lastEditedNode = nil
        onlyCameraMoved = false
        hasPendingClipEdit = true
        hasPendingInputChange = true
        reevaluate()
    }

    /// Whether something every effect reads moved since the last pass, so the
    /// next one has to drop every remembered clip.
    ///
    /// Its own flag rather than read off "no clip was named". Adding, deleting
    /// or hiding a lane names no clip either, and those used to drop the cache
    /// as well: placing one plain image on a real project (80 clips, 3 scripts)
    /// took 12.5s in debug and put a spinner on all 81 blocks. The cache
    /// compares each clip whole, so a structural edit leaves the untouched ones
    /// exactly right — only the song or the tempo moving makes all of them
    /// stale.
    @ObservationIgnored private var hasPendingInputChange = false

    private func reevaluate() {
        // During a gesture, wait for the hand to settle.
        //
        // A slider dragged across its range fires dozens of times a second, and
        // each one starts an evaluation that the next cancels — measured, eight
        // a second at 66ms each, which is half the frame budget spent on work
        // thrown away. Nobody can read a value that changes forty times a
        // second anyway: what a hand wants is the picture where it stopped.
        if isGestureActive {
            pendingEvaluation?.cancel()
            pendingEvaluation = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.evaluateNow() }
            }
            return
        }
        evaluateNow()
    }

    /// Re-reads every script file and redraws.
    ///
    /// Deliberately **not** an edit. It does not write through `effects`, so
    /// `EditHistory` never sees it and no undo entry appears: an app-side undo
    /// cannot rewrite a file on disk, and offering one would let the document
    /// and the file disagree silently. It does not mark the project dirty
    /// either — the change already happened, in a file the author owns.
    ///
    /// Resolution happens inside the evaluation pass, so this only has to ask
    /// for one.
    public func reloadScripts() {
        refreshScriptSnippets()
        effectsChanged()
    }

    /// `document` with every script node's code read from its file.
    ///
    /// A pass-through when there is no project folder yet: a document built in
    /// memory — which is every test that never opens one — has nothing to
    /// resolve against, and its nodes already carry whatever they were given.
    private func resolvedForScripts(_ document: EffectDocument) -> EffectDocument {
        guard let projectFolder else { return document }
        return ScriptResolver(folder: projectFolder).resolving(document)
    }

    private func evaluateNow() {
        evaluationTask?.cancel()

        // Resolved here, on the snapshot, before the work leaves this actor.
        //
        // `ScriptEffect.evaluate` is synchronous and cannot throw, so it has no
        // way to reach the file its node names — and a seam called from inside
        // it would read one per node per evaluation. Doing it once on the way
        // past costs a read per distinct file per pass, and the detached task
        // receives nodes that already carry their code.
        let document = resolvedForScripts(effects)
        let evaluator = evaluator
        let revision = effectsRevision

        let cameraOnly = onlyCameraMoved
        hasPendingClipEdit = false
        let showsWorld = isEditingCamera
        // Dropped here, where what moved is still known, and pruned against the
        // document while it is settled — a pass can be cancelled halfway and
        // must not conclude anything about clips it never reached.
        if !cameraOnly {
            if hasPendingInputChange {
                cache.invalidate(node: nil)
            } else if let lastEditedNode {
                cache.invalidate(node: lastEditedNode)
            }
        }
        hasPendingInputChange = false
        cache.prune(keeping: Set(document.nodes.map(\.id)))

        // Only the clips the pass will actually run, not every clip in the
        // project. Marking all of them puts a spinner on eighty blocks when one
        // changed — which is both a lie and eighty rows rebuilt to tell it.
        // A camera edit re-runs no clip, so no clip is catching up.
        let pending = cameraOnly ? [] : cache.staleNodes(in: document)
        // Only when it actually changes: writing the same value to observed
        // state still invalidates every view reading it, and during a drag that
        // is the whole timeline rebuilt per step for no visible difference.
        if evaluatingNodes != pending { evaluatingNodes = pending }
        // A camera pass re-runs no clip, so no clip shows a spinner — the
        // camera carries its own, or nothing says the picture is catching up.
        if isApplyingCamera != cameraOnly { isApplyingCamera = cameraOnly }

        let cache = cache

        // Detached from the outset, not a main-actor task that hands work off.
        //
        // `Task { }` inherits the actor it was made on, so this one queued
        // *behind* whatever the main thread was doing — measured after a resize
        // gesture, 1,098ms before it even started, against 552ms of actual
        // work. That wait is the pause between letting go of a clip and the
        // spinner appearing.
        evaluationTask = Task.detached(priority: .userInitiated) { [weak self] in
            let sprites = cache.sprites(for: document, using: evaluator)
            // The world as well, while the camera is being edited: every clip
            // is already cached by the line above, so this is the lanes
            // gathered again without the camera — no clip runs twice.
            let world = showsWorld
                ? cache.sprites(for: document, using: evaluator, applyingCamera: false)
                : nil

            guard !Task.isCancelled else { return }

            // Measured by the cache as each clip was evaluated, so a tail
            // always describes the same version of the clip as its sprites.
            // Read here, off the main thread, because the timeline reads them
            // on every rebuild.
            let (tails, seams) = cache.measurements(for: document)

            await MainActor.run {
                guard let self, self.effectsRevision == revision else { return }

                // Assigned whole: a completed pass has an entry for every clip
                // in the document, and only those — so a deleted clip's tail
                // goes with it and an untouched clip keeps the one it had.
                self.tails = tails
                self.seams = seams
                self.evaluated = sprites
                self.world = world
                if !self.evaluatingNodes.isEmpty { self.evaluatingNodes = [] }
                if self.isApplyingCamera { self.isApplyingCamera = false }
                self.adoptScriptDeclarations()
                self.onSpritesChanged?(self.canvasSprites)
            }
        }
    }

    /// The clip the last edit touched, so only it shows as catching up.
    @ObservationIgnored private var lastEditedNode: EffectNode.ID?

    /// Which clips are being rebuilt right now.
    ///
    /// Shown on the clip rather than as a window-wide spinner: a bar across the
    /// top says the app is busy, which is not the question — what someone wants
    /// to know is whether the thing they just edited has caught up.
    public private(set) var evaluatingNodes: Set<EffectNode.ID> = []

    /// Whether a camera edit is still being baked into the picture.
    public private(set) var isApplyingCamera = false

    @ObservationIgnored private var evaluationTask: Task<Void, Never>?

    /// What each clip produced last pass, so an edit re-runs only what it moved.
    ///
    /// Not observed, for the reason the other caches here are not: a cache is
    /// not state anyone should redraw for, and one written from a pass that
    /// lands mid-frame would invalidate the views that had just read it.
    ///
    /// A reference, so a pass fills it as it goes rather than handing it back
    /// at the end — see `EvaluationCache`. Every edit cancels the pass before
    /// it, and a result kept until completion is one a run of quick edits never
    /// keeps at all.
    @ObservationIgnored private let cache = EvaluationCache()

    /// Waits for any pending evaluation to land.
    ///
    /// Needed wherever the sprites are the *output* rather than the picture:
    /// exporting mid-pass would write what was on screen a moment ago, which
    /// was impossible while evaluation was inline and is a real window now.
    /// The canvas does not wait — showing the last good frame is exactly right
    /// there.
    public func awaitEvaluation() async {
        await evaluationTask?.value
    }

    /// Sprite count of the storyboard the current tracks were built from.
    ///
    /// SwiftUI calls this from both `onAppear` and `onChange`, and rebuilding
    /// mutates observed state — which would feed straight back into another
    /// update. Rebuilding only when the content actually changed breaks that.
    private var loadedSpriteCount: Int?

    /// Reads the assets a parsed storyboard references.
    ///
    /// Tracks are no longer derived from the file: they are lanes the user
    /// authors. The assets panel still reads it, which is what that panel is
    /// for.
    public func load(sprites: [PreparedSprite], missingImagePaths: Set<String>) {
        guard loadedSpriteCount != sprites.count else { return }
        loadedSpriteCount = sprites.count

        var counts: [String: Int] = [:]
        for sprite in sprites {
            for path in sprite.texturePaths { counts[path, default: 0] += 1 }
        }
        usageCounts = counts
        rebuildAssets(missing: missingImagePaths)
    }

    /// How many sprites reference each path, from the last load.
    @ObservationIgnored private var usageCounts: [String: Int] = [:]
    /// Paths a sprite names and the folder does not have.
    @ObservationIgnored private var missingPaths: Set<String> = []

    /// The image files the folder holds, supplied by the app.
    ///
    /// The panel used to list **what the storyboard referenced**, which is a
    /// different question and the wrong one: it answered "what have you used"
    /// where an assets panel is asked "what do you have". So a file sitting in
    /// the folder waiting to be placed never appeared — the one case where
    /// looking at the panel is the whole point.
    ///
    /// It also filled with things that are not the mapper's: the app's own
    /// built-in particles and the hashed glyphs a text effect mints live inside
    /// the binary, so they have no thumbnail to show and no folder to be
    /// dragged from.
    public func loadFolderAssets(_ paths: [String]) {
        folderPaths = paths
        rebuildAssets(missing: missingPaths)
    }

    @ObservationIgnored private var folderPaths: [String] = []

    /// The beatmap's own song, as a path in the folder — named by the loader,
    /// which read it from the `.osu`. Hidden from the audio assets because
    /// placing it as a sample would play the song twice over itself.
    ///
    /// `nil` hides nothing: with no known song there is no honest way to pick
    /// one, and guessing "the first audio file" would hide a hit sound.
    public var songPath: String? {
        didSet { rebuildAssets(missing: missingPaths) }
    }

    private func rebuildAssets(missing: Set<String>) {
        missingPaths = missing

        // Case-insensitive: the folder index lowercases its paths, the loader's
        // URL keeps the file's own casing.
        let song = songPath?.lowercased()

        assets = folderPaths
            .filter { path in
                guard let song else { return true }
                return !(AssetItem.Kind.inferred(from: path) == .audio && path.lowercased() == song)
            }
            .map { path in
                AssetItem(
                    id: path,
                    name: (path as NSString).lastPathComponent,
                    path: path,
                    kind: AssetItem.Kind.inferred(from: path),
                    useCount: usageCounts[path] ?? 0,
                    isMissing: missing.contains(path),
                )
            }
            // Most used first, then by name.
            //
            // Use count still leads because it says which files matter to this
            // storyboard, and a folder can hold dozens. The name breaks ties so
            // the unused ones — all zero — are in an order somebody can scan
            // rather than whatever the file system happened to return.
            .sorted { ($0.useCount, $1.name) > ($1.useCount, $0.name) }
    }



}

// ─── Range merging ───────────────────────────────────────────────────────────

/// Collapses sprite lifetimes into the spans a track draws.
///
/// Kept separate from the model so it stays a pure function: it is the only
/// non-obvious logic here, and it is worth testing without a main actor.
enum TrackRanges {
    /// A track showing thousands of individual bars is unreadable and slow, so
    /// spans closer together than this are merged. Half a second reads as one
    /// continuous run at any zoom a whole-track view uses.
    static let gapThreshold: Double = 500

    static func merged(of sprites: [PreparedSprite]) -> [ClosedRange<Double>] {
        let sorted = sprites
            .map { $0.activeStart...Swift.max($0.activeStart, $0.activeEnd) }
            .sorted { $0.lowerBound < $1.lowerBound }
        guard var current = sorted.first else { return [] }

        var merged: [ClosedRange<Double>] = []

        for range in sorted.dropFirst() {
            if range.lowerBound <= current.upperBound + gapThreshold {
                current = current.lowerBound...Swift.max(current.upperBound, range.upperBound)
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }
}

/// What a library preview is wanted for.
///
/// Outside the model because `@Observable` cannot carry a nested enum — its
/// macro tries to give every member an accessor.
public enum PreviewSubject: Sendable {
    case effect(EffectDescriptor)
    case filter(FilterDescriptor)
    case preset(EffectPreset)
}

public extension PreviewSubject {
    /// What a preview is cached under — distinct across the three kinds, so a
    /// filter and an effect that happen to share a type name never share a
    /// picture.
    var key: String {
        switch self {
        case let .effect(descriptor): "effect:" + descriptor.type
        case let .filter(descriptor): "filter:" + descriptor.type
        case let .preset(preset): "preset:" + preset.id
        }
    }
}

/// One script file and the clips that run it.
///
/// Outside the model for the reason `PreviewSubject` is: `@Observable`
/// tries to give every member of the class an accessor.
public struct ScriptEntry: Equatable, Identifiable {
    public var id: String { file.name }
    public let file: ScriptFile
    /// The first lines of the file, empty when it is missing.
    public let snippet: [String]
    public let isMissing: Bool
    /// Every clip naming the file, earliest first — so the first is the
    /// one a click on the card selects.
    public let clipIDs: [EffectNode.ID]
    /// The lane the first clip is on, for the card's colour.
    public let trackID: EffectTrack.ID?
}
