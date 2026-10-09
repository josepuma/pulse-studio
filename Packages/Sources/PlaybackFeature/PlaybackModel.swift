import Foundation
import StoryboardCore
import StoryboardPersistence
import StoryboardRendering

/// Playback clock and renderer statistics.
///
/// When the beatmap has audio, the clock follows the audio device: a display
/// link and an audio device drift apart, and a storyboard driven by anything
/// but the audio slides out of sync with the music. Without audio it falls back
/// to accumulating frame deltas.
@MainActor
@Observable
public final class PlaybackModel {
    /// Current position, in milliseconds.
    /// Told whenever the clock moves.
    ///
    /// A callback rather than something to read: anything that reads the time
    /// in a `body` is rebuilt sixty times a second, and the editor shell has no
    /// business redrawing for a clock it does not display.
    @ObservationIgnored public var onTimeChanged: ((Double) -> Void)?

    /// The audio file behind the beatmap, for an export to take its sound from.
    @ObservationIgnored public private(set) var trackURL: URL?

    /// Told when the audio has loaded and `trackURL` is real.
    ///
    /// A callback because the track arrives *after* whoever wants it has been
    /// wired up: the folder opens first and the audio loads asynchronously, so
    /// anything that captured this URL at wiring time captured `nil`.
    @ObservationIgnored public var onTrackLoaded: ((URL) -> Void)?

    /// Renders the storyboard to a video file.
    ///
    /// Installed by the canvas, which owns the renderer. Held here so the app
    /// can reach it without the renderer becoming public — an export is the
    /// only thing outside this feature that needs to draw a frame, and it needs
    /// no more of the renderer than this.
    @ObservationIgnored
    public var writeVideo: (
        (URL, ClosedRange<Double>, @escaping @Sendable (Double) -> Void) async throws -> Void
    )?

    public private(set) var currentTime: Double = 0 {
        didSet { onTimeChanged?(currentTime) }
    }
    public private(set) var isPlaying = false
    /// How far playback runs: the length of the track.
    public private(set) var duration: Double = 1

    /// The span the timeline shows.
    ///
    /// A storyboard is not bound to its track: an intro can begin before the
    /// first note and a fade can end after the last. Those are exactly the
    /// commands an editor has to show — clipping the ruler to the audio would
    /// hide the sprites whose timing is hardest to get right. So the timeline
    /// covers whichever span is wider while the transport still stops with the
    /// music.
    public private(set) var timelineRange: ClosedRange<Double> = 0...1

    /// A stretch to loop within, when something is being worked on in isolation.
    ///
    /// Editing one clip's keyframes, playback belongs to that clip: running on
    /// past its end carries the playhead somewhere the ruler no longer reaches,
    /// and every property reads as whatever its last key left behind. `nil`
    /// plays the whole timeline.
    public var loopRange: ClosedRange<Double>?

    /// What playback is currently bounded by.
    private var playbackRange: ClosedRange<Double> {
        loopRange ?? timelineRange
    }

    public private(set) var spriteCount = 0
    public private(set) var drawnCount = 0
    public private(set) var framesPerSecond: Double = 0
    public private(set) var status: Status = .loading
    public private(set) var hasAudio = false

    /// Which stage the storyboard is drawn on.
    ///
    /// Taken from the beatmap's own `WidescreenStoryboard` setting, and
    /// overridable: a map can be authored for one and still worth checking
    /// against the other.
    public var isWidescreen = true

    /// What the beatmap itself asks for, so the override can be undone.
    public private(set) var beatmapIsWidescreen = true

    /// The canvas fills the window, hiding the panels and timeline.
    ///
    /// Full screen for the storyboard rather than for the window: the point is
    /// to see the picture without the editor around it, which a full-screen
    /// window with all its panels still showing does not give.
    public var isCanvasFullScreen = false

    /// Whether the stage's centre lines are drawn over the canvas.
    ///
    /// The same landmarks a drag snaps to, shown all the time rather than only
    /// while something is caught on one. Placing by eye needs to see where the
    /// middle *is*, and a guide that appears only mid-drag cannot be aimed at
    /// beforehand.
    ///
    /// Off by default: the canvas is the picture, and a line across it is the
    /// one thing that is not part of the storyboard.
    public var showsGuides = false

    /// Timing and metadata from the beatmap, when it has a readable `.osu`.
    public private(set) var timing: BeatmapTimingData?

    /// The prepared sprites, for panels that describe the storyboard's
    /// contents rather than draw them.
    public private(set) var sprites: [PreparedSprite] = []

    /// Image paths the storyboard references that are not on disk.
    public private(set) var missingImagePaths: Set<String> = []

    /// Peaks for drawing the audio behind the timeline, once extracted.
    public private(set) var waveform: Waveform?

    public var breaks: [BreakPeriod] { timing?.breaks ?? [] }

    /// Kiai sections, clamped to the track — the parser leaves a section that
    /// is still on at the last timing point open past the end.
    public var kiaiSections: [KiaiSection] {
        (timing?.kiaiSections ?? []).map { section in
            KiaiSection(
                startTime: section.startTime,
                endTime: min(section.endTime, duration),
            )
        }
    }

    /// Set when audio was expected but could not be played. Playback continues
    /// on the synthetic clock.
    public private(set) var audioWarning: String?

    private let audio = AudioPlayer()

    // ─── Samples ─────────────────────────────────────────────────────────────

    /// Starts a sample `delay` wall-clock ms from now. Nil plays it on the
    /// audio player's own sample voices; a test records instead, since CI has
    /// no audio device.
    @ObservationIgnored public var sampleSink: ((StoryboardSample, Double) -> Void)?

    /// Cuts every sounding sample. Same seam, same reason.
    @ObservationIgnored public var sampleCancel: (() -> Void)?

    /// Which sounds are due as the clock moves. Starts inclusive at 0 so a
    /// sample on the first instant sounds when play is pressed there.
    @ObservationIgnored private var sampleSchedule: SampleSchedule = {
        var schedule = SampleSchedule()
        schedule.reset(at: 0, inclusive: true)
        return schedule
    }()

    /// The samples the storyboard places, as the shell's document lists them.
    ///
    /// Only the schedule: decoding the files is `loadSampleFiles`, which the
    /// app calls beside this one, because decoding needs the beatmap folder
    /// and this feature knows nothing about it.
    public func samplesChanged(_ samples: [StoryboardSample]) {
        sampleSchedule.samples = samples
    }

    /// Decodes the sample files off the main thread and returns the paths that
    /// cannot be played, each with why.
    public func loadSampleFiles(
        _ samples: [StoryboardSample], resolve: @Sendable (String) -> URL?,
    ) async -> [String: SamplePreviewIssue] {
        await audio.samples.load(samples, resolve: resolve)
        return audio.samples.unplayable
    }

    private func cancelSamples() {
        if let sampleCancel { sampleCancel() } else { audio.samples.stopAll() }
    }

    /// The window restarts wherever the clock now is: a seek, a loop, a rate
    /// change or a resume. Whatever was handed over for the old position is
    /// cut first, or it would sound at the wrong moment.
    private func restartSamples(inclusive: Bool) {
        cancelSamples()
        sampleSchedule.reset(at: currentTime, inclusive: inclusive)
    }

    private func fireSamples() {
        guard isPlaying else { return }
        for fire in sampleSchedule.advance(
            to: currentTime, rate: rate, lookahead: SampleSchedule.lookahead,
        ) {
            if let sampleSink {
                sampleSink(fire.sample, fire.delay)
            } else {
                audio.samples.play(path: fire.sample.path, volume: fire.sample.volume, after: fire.delay)
            }
        }
    }

    public enum Status: Equatable, Sendable {
        case loading
        case ready(String)
        case failed(String)

        public var message: String {
            switch self {
            case .loading: "Loading…"
            case let .ready(name): name
            case let .failed(reason): reason
            }
        }

        public var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }

        public var isLoading: Bool { self == .loading }
    }

    public init() {}

    // ─── Gameplay overlay ────────────────────────────────────────────────────

    /// Whether the editor draws the map's hit objects over the storyboard.
    ///
    /// Off by default and not part of the project: it is a way of looking, like
    /// the canvas zoom, so it neither dirties the document nor writes an undo
    /// step. The first enable is what parses the hit objects.
    public var showsGameplayOverlay = false {
        didSet { if showsGameplayOverlay { loadGameplayIfNeeded() } }
    }

    /// The difficulties the picker offers; empty when the source has none.
    public private(set) var gameplayDifficulties: [GameplayDifficultyOption] = []

    /// The difficulty the overlay shows.
    public private(set) var selectedGameplayDifficultyPath: String?

    /// The picker's label for the selection.
    public var selectedGameplayDifficultyName: String? {
        gameplayDifficulties.first { $0.path == selectedGameplayDifficultyPath }?.name
    }

    /// The parsed difficulty, once it has been asked for.
    ///
    /// Ignored by observation: the canvas reads it from `draw(in:)`, and a view
    /// that rebuilt when it landed would be a view watching the overlay's data
    /// instead of the toggle.
    @ObservationIgnored public private(set) var gameplayMap: GameplayMap?
    @ObservationIgnored private var gameplayLoader: (@Sendable (String) -> GameplayMap?)?
    @ObservationIgnored private var gameplayTask: Task<Void, Never>?
    /// Bumped when what is being loaded stops being what is wanted, so a slow
    /// parse of the previous difficulty cannot land over the new one.
    @ObservationIgnored private var gameplayGeneration = 0

    /// Wires the overlay to a source's difficulties, back to its defaults.
    ///
    /// Called when a storyboard opens: another project is another set of hit
    /// objects, so the toggle goes off and the choice returns to the default.
    /// Nothing is parsed here.
    public func connectGameplay(
        difficulties: [GameplayDifficultyOption],
        defaultPath: String?,
        loader: (@Sendable (String) -> GameplayMap?)?,
    ) {
        resetGameplay()
        gameplayDifficulties = difficulties
        selectedGameplayDifficultyPath = defaultPath ?? difficulties.first?.path
        gameplayLoader = loader
    }

    /// Switches the overlay to another difficulty. Parses only when it is on.
    public func selectGameplayDifficulty(_ path: String) {
        guard gameplayDifficulties.contains(where: { $0.path == path }),
              path != selectedGameplayDifficultyPath
        else { return }
        selectedGameplayDifficultyPath = path
        invalidateGameplayLoad()
        loadGameplayIfNeeded()
    }

    /// Waits for a load in flight; for tests, which have to look after it.
    public func settledGameplay() async {
        await gameplayTask?.value
    }

    private func resetGameplay() {
        invalidateGameplayLoad()
        showsGameplayOverlay = false
        gameplayDifficulties = []
        selectedGameplayDifficultyPath = nil
        gameplayLoader = nil
    }

    private func invalidateGameplayLoad() {
        gameplayGeneration &+= 1
        gameplayTask?.cancel()
        gameplayTask = nil
        gameplayMap = nil
    }

    /// Parses the selected difficulty, off the main thread, the first time it
    /// is wanted.
    ///
    /// The detached work captures the loader and the path as values: reading a
    /// main-actor property inside it would hop back to the main thread and take
    /// the parse with it — the trap that cost 1.5 s once with the audio
    /// analyser.
    private func loadGameplayIfNeeded() {
        guard showsGameplayOverlay, gameplayMap == nil, gameplayTask == nil,
              let path = selectedGameplayDifficultyPath, let loader = gameplayLoader
        else { return }
        let generation = gameplayGeneration
        gameplayTask = Task.detached(priority: .userInitiated) { [weak self, loader, path] in
            let map = loader(path)
            await self?.finishGameplayLoad(map, generation: generation)
        }
    }

    private func finishGameplayLoad(_ map: GameplayMap?, generation: Int) {
        guard generation == gameplayGeneration else { return }
        gameplayMap = map
        gameplayTask = nil
    }

    // ─── Content ─────────────────────────────────────────────────────────────

    /// The storyboard has started loading.
    public func contentLoading() {
        status = .loading
    }

    /// Releases the storyboard and stops the audio.
    ///
    /// Leaving the editor has to actually let go: without this the track keeps
    /// playing behind the project browser and the sprites stay resident, so
    /// opening a second beatmap adds to the first rather than replacing it.
    public func unload() {
        cancelSamples()
        sampleSchedule.samples = []
        audio.samples.unload()
        audio.unload()
        sprites = []
        beatmapSprites = []
        effectSprites = []
        spriteCount = 0
        drawnCount = 0
        currentTime = 0
        duration = 1
        timelineRange = 0...1
        isPlaying = false
        hasAudio = false
        audioWarning = nil
        waveform = nil
        timing = nil
        missingImagePaths = []
        resetGameplay()
        isCanvasFullScreen = false
        status = .loading
        sampleSchedule.reset(at: 0, inclusive: true)
    }

    /// Sprites the placed effects evaluate to, kept apart from the ones parsed
    /// out of the beatmap.
    ///
    /// Separate because they change for different reasons: the parsed sprites
    /// arrive once when a folder opens, while these are rebuilt whenever a
    /// parameter moves. Merging them into one array would mean re-preparing the
    /// whole storyboard on every drag.
    private var effectSprites: [PreparedSprite] = []
    private var beatmapSprites: [PreparedSprite] = []

    /// Replaces the sprites the placed effects produce.
    ///
    /// Takes finished storyboard sprites rather than the effects themselves:
    /// this feature renders what it is handed and knows nothing about emitters,
    /// which is what keeps the two features independent.
    public func effectsChanged(to storyboardSprites: [StoryboardSprite]) {
        effectSprites = StoryboardResolver.prepare(storyboardSprites)
        rebuildSprites()
    }

    /// Bumped whenever the sprite list changes, so the canvas knows to upload
    /// it again.
    ///
    /// The renderer keeps its own copy on the GPU, uploaded once. Changing
    /// `sprites` alone leaves it drawing whatever it was given at load — the
    /// new sprites exist in the model, are counted, and never appear.
    public private(set) var spritesRevision = 0

    /// Combines the beatmap's sprites with the effects placed on top.
    ///
    /// Effects go last so they draw above the parsed storyboard within their
    /// layer, the way a newly added clip lands on top in any editor.
    private func rebuildSprites() {
        sprites = beatmapSprites + effectSprites
        spriteCount = sprites.count
        spritesRevision &+= 1
    }

    public func contentLoaded(
        name: String,
        sprites: [PreparedSprite],
        duration: Double,
        audioURL: URL?,
        timing: BeatmapTimingData? = nil,
        missingImagePaths: Set<String> = [],
    ) {
        beatmapSprites = sprites
        rebuildSprites()
        // Another storyboard is another picture: it opens fitted, not wherever
        // the last one was being looked at.
        canvasViewport.fit()
        let storyboardRange = StoryboardResolver.timeRange(of: sprites)
        self.duration = max(duration, 1)
        timelineRange = storyboardRange
        self.timing = timing
        self.missingImagePaths = missingImagePaths
        status = .ready(name)

        // A beatmap with no `.osu` to read is assumed wide, which is what
        // storyboards have been authored for since the setting existed.
        beatmapIsWidescreen = timing?.isWidescreen ?? true
        isWidescreen = beatmapIsWidescreen

        // Paused on arrival: opening a beatmap is a step towards editing it,
        // not a request to play it, and music starting on its own is startling
        // rather than helpful.
        guard let audioURL else {
            hasAudio = false
            return
        }

        do {
            try audio.load(url: audioURL)
            trackURL = audioURL
            onTrackLoaded?(audioURL)
            hasAudio = true
            audioWarning = nil
            loadWaveform(from: audioURL)
            // The track defines how long the map is. A storyboard's last
            // command can sit far past the music — a loop left open, or a fade
            // ending at some enormous timestamp — and using that would leave
            // the transport running long after the audio stopped.
            self.duration = audio.duration
            // The ruler spans both, so commands that start before the track or
            // run past its end stay visible and editable.
            timelineRange = min(storyboardRange.lowerBound, 0)...max(
                storyboardRange.upperBound,
                audio.duration,
            )
        } catch {
            hasAudio = false
            audioWarning = String(describing: error)
        }
    }

    /// Reads the track's peaks off the main thread.
    ///
    /// Walking a several-minute file takes long enough to stall a frame, and
    /// the waveform is decoration: playback starts without waiting for it.
    private func loadWaveform(from url: URL) {
        waveform = nil
        // `.userInitiated` rather than `.utility`: the waveform is decoration,
        // but it is decoration someone is waiting to see — at the lowest
        // priority it can sit behind other work long enough to arrive well
        // after the storyboard is already playing.
        Task.detached(priority: .userInitiated) {
            guard let extracted = try? WaveformExtractor.extract(from: url) else { return }
            await MainActor.run { self.waveform = extracted }
        }
    }

    public func contentFailed(_ reason: String) {
        status = .failed(reason)
        isPlaying = false
    }

    // ─── Transport ───────────────────────────────────────────────────────────

    public func togglePlayback() {
        isPlaying ? pause() : startPlayback()
    }

    public func startPlayback() {
        guard !status.isFailure else { return }

        // Restart from the top when resuming at the end — the end of the
        // timeline, not of the track: pressing play on a storyboard's closing
        // seconds should play them, not jump back to the beginning.
        if currentTime >= playbackRange.upperBound - 1 {
            seek(to: playbackRange.lowerBound)
        }

        // Only while the playhead is within the track. Outside it, `advance`
        // runs the clock on its own and starts the audio when the playhead
        // arrives, so a lead-in or a tail plays out in silence as it should.
        if hasAudio, currentTime >= 0, currentTime < duration { audio.play() }
        isPlaying = true
    }

    public func pause() {
        if hasAudio { audio.pause() }
        isPlaying = false
        // Exclusive: what sounded before the pause must not sound again on
        // resume, while what was only handed over, and is now cut, is
        // re-handed by the reset at this instant.
        restartSamples(inclusive: false)
    }

    /// Clamps and applies a seek, in milliseconds.
    ///
    /// The clock follows the timeline, which can open before the track does —
    /// a storyboard is allowed to start early, and scrubbing has to reach the
    /// sprites that live there. The audio is clamped separately, since it has
    /// nothing to play before its own first sample.
    public func seek(to time: Double) {
        // Clamped to whatever playback is bounded by, so scrubbing cannot
        // leave the stretch being worked on either.
        currentTime = min(max(playbackRange.lowerBound, time), playbackRange.upperBound)
        restartSamples(inclusive: true)
        guard hasAudio else { return }

        audio.seek(toMilliseconds: min(max(0, currentTime), duration))

        // Landing outside the track silences it: scrubbing into a lead-in or a
        // tail should not leave the first or last moment of the music sounding.
        if isPlaying, currentTime < 0 || currentTime >= duration {
            audio.pause()
        }
    }

    public func setVolume(_ volume: Float) {
        audio.volume = volume
    }

    public var volume: Float { audio.volume }

    /// How far behind the audio engine may report before its position is taken
    /// as a seek rather than as it catching up.
    ///
    /// A few frames' worth: an engine just told to play lags by a frame or two,
    /// while anything further back is somebody having moved the playhead.
    /// How fast playback runs, as a multiple of the track's own tempo.
    ///
    /// Held here rather than only on the player because the clock outside the
    /// track has to scale with it too — and because a storyboard follows the
    /// audio, so this is the speed of the *preview*, not only of the sound.
    public var rate: Float = 1 {
        didSet {
            let clamped = min(max(rate, AudioPlayer.minimumRate), AudioPlayer.maximumRate)
            if clamped != rate { rate = clamped; return }
            audio.rate = rate
            if isPlaying { restartSamples(inclusive: false) }
        }
    }

    private static let audioCatchUpTolerance: Double = 250

    // ─── Frame updates ───────────────────────────────────────────────────────

    /// Advances the clock by one frame.
    ///
    /// The clock follows the timeline, not the track. A storyboard is allowed
    /// to open before the first note and to run past the last, and both of
    /// those stretches have to play: the audio is one source the clock can
    /// borrow from while it lasts, not the definition of how long the piece is.
    ///
    /// - Parameter delta: elapsed time in milliseconds, used whenever the
    ///   playhead is outside the track and has no audio clock to follow.
    public func advance(by delta: Double) {
        advanceClock(by: delta)
        fireSamples()
    }

    private func advanceClock(by delta: Double) {
        guard isPlaying else { return }

        // Outside the track, the clock runs on the frame delta and the audio
        // stays quiet — a lead-in before the music, or a tail after it.
        //
        // Scaled by the rate, because inside the track the clock follows the
        // audio and the audio is already stretched. Left at wall speed, a
        // storyboard at half rate would sprint through its lead-in and then
        // drop to half the moment the music started.
        guard currentTime >= 0, currentTime < duration, hasAudio, audio.isPlaying else {
            currentTime += delta * Double(rate)

            if currentTime > playbackRange.upperBound {
                loopToStart()
            } else if hasAudio, !audio.isPlaying, currentTime >= 0, currentTime < duration {
                // The playhead has reached the track: start it where the clock
                // already is rather than from the top.
                audio.seek(toMilliseconds: currentTime)
                audio.play()
            }
            return
        }

        // Within the track the audio hardware keeps the time, because a display
        // link and an audio device drift apart.
        //
        // Except while the engine is still catching up: told to play, it
        // reports its old position for a few frames, and taking that would snap
        // the playhead back to where the audio was rather than where the clock
        // has reached. A large jump is a seek and is followed; a small step
        // backwards is the engine lagging and is ignored.
        let reported = audio.currentTime
        let isLag = reported < currentTime && currentTime - reported < Self.audioCatchUpTolerance
        currentTime = isLag ? currentTime + delta : reported

        if audio.hasReachedEnd {
            // Past the end of the music the clock carries on by itself, so a
            // storyboard that outlasts its track still plays out.
            audio.pause()
            currentTime = duration
        }

        // The bound is checked whatever the audio is doing.
        //
        // Inside the track the clock follows the audio hardware, and asking
        // only when the *track* ran out never fires for a range in the middle
        // of a song: a two-second clip in keyframe mode looped visually while
        // the music played straight past it.
        if currentTime >= playbackRange.upperBound {
            loopToStart()
        }
    }

    private func loopToStart() {
        seek(to: playbackRange.lowerBound)
        if hasAudio, isPlaying, currentTime >= 0, currentTime < duration {
            audio.play()
        }
    }

    public func frameRendered(
        drawnCount: Int,
        framesPerSecond: Double,
        selectionBounds: ClipBounds? = nil,
        hoverBounds: ClipBounds? = nil,
    ) {
        self.drawnCount = drawnCount
        self.framesPerSecond = framesPerSecond

        // Written only when it actually moved: this runs 60 times a second, and
        // an observed property assigned every frame redraws every view that
        // reads it, whether or not anything changed.
        if selectionBounds != self.selectionBounds {
            self.selectionBounds = selectionBounds
        }
        if hoverBounds != self.hoverBounds {
            self.hoverBounds = hoverBounds
        }
    }

    /// Which clips the selection box should frame — one, or a group framed
    /// as a single box around all of it.
    ///
    /// Clearing the measurement on a change rather than leaving the old one:
    /// the bounds belong to whichever clip was measured last, so keeping them
    /// draws the previous clip's frame around the new selection until the next
    /// frame corrects it — a box that visibly jumps from the wrong place.
    public var selectedClipIDs: Set<String> = [] {
        didSet {
            guard selectedClipIDs != oldValue else { return }
            selectionBounds = nil
        }
    }

    /// Where that clip is on the stage, measured as it was last drawn.
    public private(set) var selectionBounds: ClipBounds?

    // ─── Canvas zoom ─────────────────────────────────────────────────────────

    /// How the canvas is looked at. A view onto it, never part of the
    /// storyboard: an export is always the stage.
    public var canvasViewport = CanvasViewport()

    /// The space the canvas is laid out in, so commands without a pointer —
    /// a menu, a shortcut — can zoom about its middle.
    @ObservationIgnored public var canvasContainerSize: CGSize = .zero

    /// The stage in canvas units.
    public var canvasStageSize: CGSize {
        let stage = OsuCanvas.size(widescreen: isWidescreen)
        return CGSize(width: CGFloat(stage.width), height: CGFloat(stage.height))
    }

    /// Sets the zoom about the middle of the view, the way a preset does.
    public func setCanvasZoom(_ zoom: Double) {
        let size = canvasContainerSize
        canvasViewport.zoom(
            to: zoom,
            keeping: CGPoint(x: size.width / 2, y: size.height / 2),
            container: size,
            stage: canvasStageSize,
        )
    }

    /// Zooms by a factor about a point — a pinch, or ⌘ and the wheel.
    public func zoomCanvas(by factor: Double, at point: CGPoint) {
        canvasViewport.zoom(
            to: canvasViewport.zoom * factor,
            keeping: point,
            container: canvasContainerSize,
            stage: canvasStageSize,
        )
    }

    public func panCanvas(by delta: CGSize) {
        canvasViewport.pan(by: delta, container: canvasContainerSize, stage: canvasStageSize)
    }

    public func fitCanvas() {
        canvasViewport.fit()
    }

    /// One preset in or out — what ⌘= and ⌘− do, so a keyboard zoom always
    /// lands on a number the menu can name. From between presets it goes to
    /// the next one along rather than back to the one it passed.
    public func stepCanvasZoom(in zoomingIn: Bool) {
        let current = canvasViewport.zoom
        let presets = CanvasViewport.presets
        let next = zoomingIn
            ? presets.first { $0 > current + 1e-9 } ?? presets.last
            : presets.last { $0 < current - 1e-9 } ?? presets.first
        guard let next else { return }
        setCanvasZoom(next)
    }

    // ─── Picking on the canvas ───────────────────────────────────────────────

    /// The clip under the pointer, outlined so it can be picked without
    /// hunting for it on the timeline.
    ///
    /// Not observed: the canvas reads it at draw time. What views watch is the
    /// box it produces, `hoverBounds`.
    @ObservationIgnored public var hoveredClipID: String? {
        didSet {
            guard hoveredClipID != oldValue else { return }
            // The old clip's box would outline the wrong thing for a frame.
            if hoverBounds != nil { hoverBounds = nil }
        }
    }

    /// Where the hovered clip is on the stage, as last drawn.
    public private(set) var hoverBounds: ClipBounds?

    /// The clips a click may pick — every clip not on a locked lane. Set by
    /// whoever owns the document; the canvas knows only sprites.
    @ObservationIgnored public var pickableClipIDs: () -> Set<String> = { [] }

    /// Asks the renderer which clip is drawn at a point. Installed by the
    /// canvas once its renderer exists.
    @ObservationIgnored var hitTester: (
        ((x: Double, y: Double), (String) -> String?) -> String?
    )?

    /// The clip drawn on top at a point on the stage, among those that may be
    /// picked.
    public func clip(at point: (x: Double, y: Double)) -> String? {
        let clips = pickableClipIDs()
        guard !clips.isEmpty, let hitTester else { return nil }
        return hitTester(point) { ClipBounds.owner(of: $0, among: clips) }
    }

    // ─── Drag preview ────────────────────────────────────────────────────────

    /// The clip being dragged, drawn where the drag has taken it.
    ///
    /// Not observed: the canvas reads it at draw time, and a property written
    /// per drag event and read in a body would rebuild the view per event.
    @ObservationIgnored public private(set) var clipPreview: ClipPreview?

    /// The sprite revision current when the hand came up, once it has.
    ///
    /// The committed sprites are the first revision *after* this one. Sprites
    /// already waiting at release were evaluated before the commit, and
    /// letting them end the preview would show the clip back where it was.
    @ObservationIgnored private var releasedAtRevision: Int?

    /// Draws the dragged clip where the drag has taken it.
    public func previewDrag(_ preview: ClipPreview) {
        clipPreview = preview
        releasedAtRevision = nil
    }

    /// The hand came up and the drag was committed: keep drawing the preview
    /// until the sprites carrying the commit reach the GPU.
    ///
    /// Dropped on mouse-up, the picture jumped back to where the clip had been
    /// and forward again when the evaluation landed — it runs off the main
    /// thread, so there is always a gap.
    public func releasePreview() {
        guard clipPreview != nil else { return }
        releasedAtRevision = spritesRevision
    }

    /// The drag ended without a commit: nothing is coming to replace it.
    public func cancelPreview() {
        clipPreview = nil
        releasedAtRevision = nil
    }

    /// Called by the canvas as it uploads a sprite revision, on the frame it
    /// will draw them — so the preview and the committed sprites swap without
    /// a frame of either missing.
    public func spritesUploaded(revision: Int) {
        guard let released = releasedAtRevision, revision > released else { return }
        clipPreview = nil
        releasedAtRevision = nil
    }

    // ─── Formatting ──────────────────────────────────────────────────────────

    /// Position formatted as `m:ss.hh`.
    public var timecode: String {
        Self.timecode(for: currentTime)
    }

    /// How far playback runs, which is the end of the timeline rather than of
    /// the track: the transport counts up to where the storyboard stops.
    public var durationTimecode: String {
        Self.timecode(for: timelineRange.upperBound)
    }

    private static func timecode(for milliseconds: Double) -> String {
        let totalSeconds = Int(milliseconds / 1000)
        let hundredths = Int(milliseconds.truncatingRemainder(dividingBy: 1000) / 10)
        return String(format: "%d:%02d.%02d", totalSeconds / 60, totalSeconds % 60, hundredths)
    }
}
