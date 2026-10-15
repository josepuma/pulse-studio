import Foundation

// ─── Pre-processed types ─────────────────────────────────────────────────────

/// Commands of one kind, sorted by start time.
///
/// Grouping by kind up front means each per-frame lookup is a binary search
/// over a small, already-ordered array.
struct CommandTrack: Sendable {
    var commands: [Command] = []

    /// `maxEnd[i]` is the highest `endTime` among `commands[0...i]`.
    ///
    /// Non-decreasing by construction, which is what makes "is anything at or
    /// below `i` still active at `time`?" a single comparison. Empty until
    /// ``buildPrefixIndex()`` runs; `resolve` falls back to the plain scan
    /// while the two arrays don't cover `commands`.
    private(set) var maxEnd: [Double] = []

    /// `heldIndex[i]` is the command a track holds at a time when NONE of
    /// `commands[0...i]` is active: the latest `endTime`, then the higher
    /// `startTime`, then the higher index.
    ///
    /// The old backward scan met higher indices first and replaced its
    /// candidate only on a strict improvement, so a full tie went to the
    /// higher index. Walking forward, index `i` therefore wins a tie against
    /// the running best — that is the `>=` below, and it is the one place a
    /// careless rewrite changes behaviour.
    private(set) var heldIndex: [Int] = []

    var isEmpty: Bool { commands.isEmpty }

    /// Fills the prefix arrays. Call once, after `commands` is sorted.
    ///
    /// Not a `didSet` on `commands`: `CommandTracks.init` appends command by
    /// command, and rebuilding on each append would be quadratic.
    mutating func buildPrefixIndex() {
        var ends: [Double] = []
        var held: [Int] = []
        ends.reserveCapacity(commands.count)
        held.reserveCapacity(commands.count)

        for (index, command) in commands.enumerated() {
            guard index > 0 else {
                ends.append(command.endTime)
                held.append(0)
                continue
            }
            ends.append(Swift.max(ends[index - 1], command.endTime))

            let best = commands[held[index - 1]]
            let beatsBest = command.endTime > best.endTime
                || (command.endTime == best.endTime && command.startTime >= best.startTime)
            held.append(beatsBest ? index : held[index - 1])
        }

        maxEnd = ends
        heldIndex = held
    }

    /// Index of the rightmost command whose `startTime` is at or before `time`,
    /// or `nil` when every command starts later.
    ///
    /// Ported from `upperBound` in `app/lib/engine/timeline.ts`.
    func upperBound(at time: Double) -> Int? {
        var low = 0
        var high = commands.count - 1
        var result: Int?

        while low <= high {
            let mid = (low + high) / 2
            if commands[mid].startTime <= time {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    /// The command that governs `time`.
    ///
    /// Priority rules, matching `resolveCommand` in the TypeScript source:
    /// - Among commands active at `time` (`startTime ... endTime`), the one with
    ///   the highest `startTime` wins — the most recently started.
    /// - With none active, the value of the command with the latest `endTime`
    ///   is held.
    func resolve(at time: Double) -> Command? {
        guard let index = resolvedIndex(at: time) else { return nil }
        return commands[index]
    }

    /// Index of the command ``resolve(at:)`` returns. `steps`, when given,
    /// counts every command inspected — test-only instrumentation; with `nil`
    /// (the only production call) the optimiser drops the counting.
    @inline(__always)
    func resolvedIndex(at time: Double, steps: UnsafeMutablePointer<Int>? = nil) -> Int? {
        guard !commands.isEmpty else { return nil }
        guard let ub = upperBound(at: time) else {
            // Everything starts later — hold the first command's start value.
            return 0
        }

        let indexed = maxEnd.count == commands.count

        // The gap case. A hopping sprite sits between commands most frames, and
        // the plain backward scan then walks to index 0 finding nothing: O(n)
        // in the track's length. `maxEnd[ub] < time` says no command at or
        // below `ub` reaches `time`, so the answer is precomputed.
        if indexed, maxEnd[ub] < time {
            return heldIndex[ub]
        }

        // Some command is active (or the track isn't indexed). Scanning
        // backwards, the first active one has the highest startTime, so it
        // wins. With an index a hit is guaranteed, and the scan stops at it;
        // the cost is the run of already-ended commands sitting above the
        // winner, which for a sprite's own commands is short — the winner is
        // almost always the latest or second latest.
        var held: Int?
        for index in stride(from: ub, through: 0, by: -1) {
            steps?.pointee += 1
            let command = commands[index]
            if time <= command.endTime {
                return index
            }
            if !indexed {
                if let current = held {
                    let best = commands[current]
                    if command.endTime > best.endTime
                        || (command.endTime == best.endTime && command.startTime > best.startTime)
                    {
                        held = index
                    }
                } else {
                    held = index
                }
            }
        }
        return held ?? 0
    }
}

/// Commands grouped by kind, each track sorted by start time.
struct CommandTracks: Sendable {
    var fade = CommandTrack()
    var move = CommandTrack()
    var moveX = CommandTrack()
    var moveY = CommandTrack()
    var scale = CommandTrack()
    var vectorScale = CommandTrack()
    var rotate = CommandTrack()
    var color = CommandTrack()
    var parameter = CommandTrack()

    init(_ commands: [Command]) {
        for command in commands {
            switch command.kind {
            case .fade: fade.commands.append(command)
            case .move: move.commands.append(command)
            case .moveX: moveX.commands.append(command)
            case .moveY: moveY.commands.append(command)
            case .scale: scale.commands.append(command)
            case .vectorScale: vectorScale.commands.append(command)
            case .rotate: rotate.commands.append(command)
            case .color: color.commands.append(command)
            case .parameter: parameter.commands.append(command)
            }
        }

        // A stable sort keeps same-start commands in file order, matching
        // JavaScript's `Array.prototype.sort`.
        fade.commands.stableSortByStartTime()
        move.commands.stableSortByStartTime()
        moveX.commands.stableSortByStartTime()
        moveY.commands.stableSortByStartTime()
        scale.commands.stableSortByStartTime()
        vectorScale.commands.stableSortByStartTime()
        rotate.commands.stableSortByStartTime()
        color.commands.stableSortByStartTime()
        parameter.commands.stableSortByStartTime()

        fade.buildPrefixIndex()
        move.buildPrefixIndex()
        moveX.buildPrefixIndex()
        moveY.buildPrefixIndex()
        scale.buildPrefixIndex()
        vectorScale.buildPrefixIndex()
        rotate.buildPrefixIndex()
        color.buildPrefixIndex()
        parameter.buildPrefixIndex()
    }
}

/// A loop group with its body pre-grouped and its iteration length computed.
struct PreparedLoop: Sendable {
    var startTime: Double
    /// One iteration's length: the highest relative `endTime` in the body.
    var loopDuration: Double
    var loopCount: Int
    var tracks: CommandTracks

    var endTime: Double { startTime + Double(loopCount) * loopDuration }

    init?(_ loop: LoopGroup) {
        guard !loop.commands.isEmpty else { return nil }
        let duration = loop.commands.reduce(0.0) { Swift.max($0, $1.endTime) }
        guard duration > 0 else { return nil }

        startTime = loop.startTime
        loopDuration = duration
        loopCount = loop.loopCount
        tracks = CommandTracks(loop.commands)
    }
}

/// A sprite prepared for per-frame resolution.
///
/// Build once with ``StoryboardResolver/prepare(_:)``, then resolve every frame.
public struct PreparedSprite: Sendable {
    public let id: String
    public let layer: Layer
    public let origin: Origin
    public let filePath: String
    public let defaultX: Double
    public let defaultY: Double
    /// First time the sprite is alive.
    public let activeStart: Double
    /// Last time the sprite is alive.
    public let activeEnd: Double
    /// Frame files of an animated sprite, built once here so the per-frame
    /// path never builds a string; `nil` for a plain sprite.
    public let framePaths: [String]?
    public let animation: SpriteAnimation?
    /// Instant the frame clock starts. Not `activeStart`: parameter flags and
    /// a loop body's own offset count here, and they do not count there.
    public let animationStart: Double

    var tracks: CommandTracks
    var loops: [PreparedLoop]
}

// ─── Resolver ────────────────────────────────────────────────────────────────

public enum StoryboardResolver {
    /// Groups and sorts each sprite's commands and computes its active window.
    ///
    /// Sprites with no commands and no loops are dropped, as are sprites whose
    /// active window cannot be determined.
    ///
    /// Ported from `prepareStoryboard` in `app/lib/engine/timeline.ts`.
    public static func prepare(_ sprites: [StoryboardSprite]) -> [PreparedSprite] {
        var prepared: [PreparedSprite] = []
        prepared.reserveCapacity(sprites.count)

        for sprite in sprites {
            guard !sprite.commands.isEmpty || !sprite.loops.isEmpty else { continue }

            var activeStart = Double.infinity
            var activeEnd = -Double.infinity

            // Parameter commands modify a sprite within its lifetime but must
            // not define that lifetime: `additive(0, 0)` is shorthand for
            // "always additive", not "alive from t = 0".
            for command in sprite.commands where command.kind != .parameter {
                activeStart = Swift.min(activeStart, command.startTime)
                activeEnd = Swift.max(activeEnd, command.endTime)
            }

            var preparedLoops: [PreparedLoop] = []
            for loop in sprite.loops {
                guard let preparedLoop = PreparedLoop(loop) else { continue }
                preparedLoops.append(preparedLoop)
                activeStart = Swift.min(activeStart, preparedLoop.startTime)
                activeEnd = Swift.max(activeEnd, preparedLoop.endTime)
            }

            guard activeStart.isFinite else { continue }

            // The animation clock counts every base command, flags included,
            // and a loop contributes where its earliest body command lands,
            // not the bare loop header time.
            var animationStart = Double.infinity
            for command in sprite.commands {
                animationStart = Swift.min(animationStart, command.startTime)
            }
            for loop in sprite.loops {
                guard let bodyStart = loop.commands.map(\.startTime).min() else { continue }
                animationStart = Swift.min(animationStart, loop.startTime + bodyStart)
            }
            if !animationStart.isFinite { animationStart = activeStart }

            prepared.append(PreparedSprite(
                id: sprite.id,
                layer: sprite.layer,
                origin: sprite.origin,
                filePath: sprite.filePath,
                defaultX: sprite.defaultX,
                defaultY: sprite.defaultY,
                activeStart: activeStart,
                activeEnd: activeEnd,
                framePaths: sprite.animation.map { AnimationFrames.paths(base: sprite.filePath, animation: $0) },
                animation: sprite.animation,
                animationStart: animationStart,
                tracks: CommandTracks(sprite.commands),
                loops: preparedLoops,
            ))
        }

        return prepared
    }

    /// Prepared sprites bucketed by when they are on screen.
    ///
    /// A storyboard is mostly not on screen at any one moment, so asking every
    /// sprite whether it is alive is a scan over work that is almost entirely
    /// wasted. Buckets turn that into a look at one slice.
    ///
    /// Buckets rather than a sorted array with a cursor, because a sprite is
    /// alive over a *span*: sorted by birth, a long-lived sprite born early
    /// keeps every later frame from skipping past it, and the scan is back.
    public struct LiveIndex: Sendable {
        public let sprites: [PreparedSprite]

        /// How wide one bucket is, in milliseconds.
        ///
        /// A second is a few dozen buckets over a song and keeps each one small
        /// enough that scanning it is nothing. Finer buckets cost memory for a
        /// scan that is already short.
        private static let bucketSpan: Double = 1000

        private let buckets: [[Int]]
        private let origin: Double

        public init(_ sprites: [PreparedSprite]) {
            self.sprites = sprites

            let starts = sprites.map(\.activeStart)
            let ends = sprites.map(\.activeEnd)
            origin = starts.min() ?? 0
            let last = ends.max() ?? origin

            let count = max(1, Int((last - origin) / Self.bucketSpan) + 1)
            var built = [[Int]](repeating: [], count: count)

            for (index, sprite) in sprites.enumerated() {
                // A sprite lands in every bucket its life touches, so a frame
                // finds it wherever it looks.
                let first = max(0, Int((sprite.activeStart - origin) / Self.bucketSpan))
                let final = min(count - 1, Int((sprite.activeEnd - origin) / Self.bucketSpan))
                guard first <= final else { continue }
                for bucket in first ... final { built[bucket].append(index) }
            }

            buckets = built
        }

        /// The sprites that might be alive at a moment.
        func candidates(at time: Double) -> [Int] {
            let bucket = Int((time - origin) / Self.bucketSpan)
            guard bucket >= 0, bucket < buckets.count else { return [] }
            return buckets[bucket]
        }
    }

    /// Resolves every sprite that is alive at `time`, in input order.
    ///
    /// Ported from `resolveStoryboard`. The TypeScript version recycles a state
    /// pool to avoid allocations; `SpriteRenderState` is a value type, so the
    /// results array is filled directly instead.
    public static func resolve(
        _ prepared: [PreparedSprite],
        at time: Double,
        into results: inout [SpriteRenderState],
    ) {
        var indices: [Int] = []
        resolve(prepared, at: time, into: &results, indices: &indices)
    }

    /// Resolves every live sprite, and says which prepared sprite each one came
    /// from.
    ///
    /// The indices exist so a caller does not have to find its way back by
    /// sprite id. The renderer needs each state's sprite to read its texture and
    /// origin, and walked the two lists in step comparing ids to stay aligned —
    /// **a string comparison per sprite per frame**, over every sprite in the
    /// storyboard rather than every live one. Measured on a grid-filtered
    /// emitter: 14,845 sprites cost 9ms a frame *with nothing drawn at all*,
    /// which is over half a 60fps budget spent finding out what to skip.
    public static func resolve(
        _ prepared: [PreparedSprite],
        at time: Double,
        into results: inout [SpriteRenderState],
        indices: inout [Int],
    ) {
        results.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)

        prepared.withUnsafeBufferPointer { buffer in
            for index in 0 ..< buffer.count {
                let sprite = buffer[index]
                guard time >= sprite.activeStart, time <= sprite.activeEnd else { continue }
                results.append(state(of: sprite, at: time))
                indices.append(index)
            }
        }
    }

    /// Resolves only the sprites an index says could be alive.
    ///
    /// A storyboard is mostly *not* on screen at any moment: measured on a
    /// grid-filtered emitter, 36 sprites drawn out of 14,845. Testing every one
    /// of them each frame is a linear scan over work that is almost entirely
    /// wasted, and it dominated the frame — 16ms of a 16.6ms budget, with the
    /// drawing itself costing 2.
    ///
    /// The index buckets sprites by when they are alive, so a frame looks at
    /// its own bucket rather than at the whole storyboard.
    public static func resolve(
        _ index: LiveIndex,
        at time: Double,
        into results: inout [SpriteRenderState],
        indices: inout [Int],
    ) {
        results.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)

        index.sprites.withUnsafeBufferPointer { buffer in
            for candidate in index.candidates(at: time) {
                let sprite = buffer[candidate]
                guard time >= sprite.activeStart, time <= sprite.activeEnd else { continue }
                results.append(state(of: sprite, at: time))
                indices.append(candidate)
            }
        }
    }

    /// Convenience wrapper that allocates a fresh results array.
    public static func resolve(
        _ prepared: [PreparedSprite],
        at time: Double,
    ) -> [SpriteRenderState] {
        var results: [SpriteRenderState] = []
        results.reserveCapacity(prepared.count)
        resolve(prepared, at: time, into: &results)
        return results
    }

    /// How long the storyboard runs, in milliseconds.
    ///
    /// The last sprite's end time is not enough on its own: one sprite with a
    /// runaway timestamp — a loop left open, a fade ending far past the music —
    /// would stretch playback to match it. A sprite ending more than a minute
    /// after the bulk of them is treated as an outlier.
    ///
    /// Use this only when there is no audio; a track's own length is the better
    /// answer whenever one exists.
    public static func duration(of prepared: [PreparedSprite]) -> Double {
        let ends = prepared.map(\.activeEnd).filter(\.isFinite).sorted()
        guard let last = ends.last else { return 1 }

        let percentileIndex = Int(Double(ends.count - 1) * 0.95)
        let percentile = ends[percentileIndex]

        return last - percentile > 60_000 ? percentile : last
    }

    /// The span the storyboard occupies, from its first command to its last.
    ///
    /// A storyboard is not bound to the track it plays over: an intro can
    /// begin before the first note and a fade can end after the last. An editor
    /// has to show both — those are exactly the commands whose timing is hard
    /// to get right and easiest to get wrong.
    ///
    /// The end is the last command, not ``duration(of:)``.
    ///
    /// That function drops a trailing outlier so playback does not run on in
    /// silence, which is right for a transport and wrong for a ruler: the
    /// timeline draws every sprite it has, and a span that stops short of the
    /// last one leaves its clip hanging past the end of the track it sits on.
    public static func timeRange(of prepared: [PreparedSprite]) -> ClosedRange<Double> {
        let starts = prepared.map(\.activeStart).filter(\.isFinite)
        let ends = prepared.map(\.activeEnd).filter(\.isFinite)

        let start = Swift.min(starts.min() ?? 0, 0)
        let end = ends.max() ?? 1

        return start...Swift.max(end, start + 1)
    }

    // ─── Per-sprite resolution ───────────────────────────────────────────────

    /// Ported from `resolveSprite`.
    static func state(of sprite: PreparedSprite, at time: Double) -> SpriteRenderState {
        var x = sprite.defaultX
        var y = sprite.defaultY
        var scaleX = 1.0
        var scaleY = 1.0
        var rotation = 0.0
        var opacity = 1.0
        var r = 255.0
        var g = 255.0
        var b = 255.0
        var additive = false
        var flipH = false
        var flipV = false

        applyTracks(
            sprite.tracks, at: time,
            x: &x, y: &y,
            scaleX: &scaleX, scaleY: &scaleY,
            rotation: &rotation, opacity: &opacity,
            r: &r, g: &g, b: &b,
        )

        // Parameters are additive flags: every command whose window contains
        // `time` contributes. A zero-length window lasts the sprite's lifetime.
        applyParameters(
            sprite.tracks.parameter, at: time,
            zeroLengthEnd: sprite.activeEnd,
            additive: &additive, flipH: &flipH, flipV: &flipV,
        )

        // ── Loop overrides ───────────────────────────────────────────────────
        var hasActiveLoop = false
        var lastEndedLoop: PreparedLoop?
        var lastEndedLoopEnd = -Double.infinity

        for loop in sprite.loops {
            guard time >= loop.startTime else { continue }

            if time >= loop.endTime {
                if loop.endTime > lastEndedLoopEnd {
                    lastEndedLoop = loop
                    lastEndedLoopEnd = loop.endTime
                }
                continue
            }

            hasActiveLoop = true
            let relativeTime = (time - loop.startTime)
                .truncatingRemainder(dividingBy: loop.loopDuration)

            applyTracks(
                loop.tracks, at: relativeTime,
                x: &x, y: &y,
                scaleX: &scaleX, scaleY: &scaleY,
                rotation: &rotation, opacity: &opacity,
                r: &r, g: &g, b: &b,
            )
            applyParameters(
                loop.tracks.parameter, at: relativeTime,
                zeroLengthEnd: loop.loopDuration,
                additive: &additive, flipH: &flipH, flipV: &flipV,
            )
        }

        // With no loop active but one finished, hold its terminal state — but
        // only for properties no direct command already drives.
        if !hasActiveLoop, let terminal = lastEndedLoop {
            let terminalTime = terminal.loopDuration

            if sprite.tracks.move.isEmpty, let command = terminal.tracks.move.resolve(at: terminalTime),
               case let .move(startX, startY, endX, endY) = command.payload
            {
                x = eased(command, terminalTime, startX, endX)
                y = eased(command, terminalTime, startY, endY)
            }
            if sprite.tracks.moveX.isEmpty, let command = terminal.tracks.moveX.resolve(at: terminalTime),
               case let .moveX(start, end) = command.payload
            {
                x = eased(command, terminalTime, start, end)
            }
            if sprite.tracks.moveY.isEmpty, let command = terminal.tracks.moveY.resolve(at: terminalTime),
               case let .moveY(start, end) = command.payload
            {
                y = eased(command, terminalTime, start, end)
            }
            if sprite.tracks.scale.isEmpty, let command = terminal.tracks.scale.resolve(at: terminalTime),
               case let .scale(start, end) = command.payload
            {
                let value = eased(command, terminalTime, start, end)
                scaleX = value
                scaleY = value
            }
            if sprite.tracks.vectorScale.isEmpty,
               let command = terminal.tracks.vectorScale.resolve(at: terminalTime),
               case let .vectorScale(startX, startY, endX, endY) = command.payload
            {
                scaleX = eased(command, terminalTime, startX, endX)
                scaleY = eased(command, terminalTime, startY, endY)
            }
            if sprite.tracks.rotate.isEmpty, let command = terminal.tracks.rotate.resolve(at: terminalTime),
               case let .rotate(start, end) = command.payload
            {
                rotation = eased(command, terminalTime, start, end)
            }
            if sprite.tracks.fade.isEmpty, let command = terminal.tracks.fade.resolve(at: terminalTime),
               case let .fade(start, end) = command.payload
            {
                opacity = eased(command, terminalTime, start, end)
            }
            if sprite.tracks.color.isEmpty, let command = terminal.tracks.color.resolve(at: terminalTime),
               case let .color(startR, startG, startB, endR, endG, endB) = command.payload
            {
                r = eased(command, terminalTime, startR, endR)
                g = eased(command, terminalTime, startG, endG)
                b = eased(command, terminalTime, startB, endB)
            }
        }

        return SpriteRenderState(
            spriteId: sprite.id,
            x: x, y: y,
            scaleX: scaleX, scaleY: scaleY,
            rotation: rotation,
            opacity: opacity,
            r: r, g: g, b: b,
            visible: opacity > 0,
            additive: additive,
            flipH: flipH,
            flipV: flipV,
            frameIndex: sprite.animation.map {
                AnimationFrames.index(at: time, origin: sprite.animationStart, animation: $0)
            } ?? 0,
        )
    }

    /// Applies every non-parameter track, in the order the TypeScript resolver
    /// uses: `MX`/`MY` override `M`, and `V` overrides `S`.
    private static func applyTracks(
        _ tracks: CommandTracks,
        at time: Double,
        x: inout Double, y: inout Double,
        scaleX: inout Double, scaleY: inout Double,
        rotation: inout Double, opacity: inout Double,
        r: inout Double, g: inout Double, b: inout Double,
    ) {
        if let command = tracks.move.resolve(at: time),
           case let .move(startX, startY, endX, endY) = command.payload
        {
            x = eased(command, time, startX, endX)
            y = eased(command, time, startY, endY)
        }
        if let command = tracks.moveX.resolve(at: time),
           case let .moveX(start, end) = command.payload
        {
            x = eased(command, time, start, end)
        }
        if let command = tracks.moveY.resolve(at: time),
           case let .moveY(start, end) = command.payload
        {
            y = eased(command, time, start, end)
        }

        if let command = tracks.scale.resolve(at: time),
           case let .scale(start, end) = command.payload
        {
            let value = eased(command, time, start, end)
            scaleX = value
            scaleY = value
        }
        if let command = tracks.vectorScale.resolve(at: time),
           case let .vectorScale(startX, startY, endX, endY) = command.payload
        {
            scaleX = eased(command, time, startX, endX)
            scaleY = eased(command, time, startY, endY)
        }

        if let command = tracks.rotate.resolve(at: time),
           case let .rotate(start, end) = command.payload
        {
            rotation = eased(command, time, start, end)
        }
        if let command = tracks.fade.resolve(at: time),
           case let .fade(start, end) = command.payload
        {
            opacity = eased(command, time, start, end)
        }
        if let command = tracks.color.resolve(at: time),
           case let .color(startR, startG, startB, endR, endG, endB) = command.payload
        {
            r = eased(command, time, startR, endR)
            g = eased(command, time, startG, endG)
            b = eased(command, time, startB, endB)
        }
    }

    /// Ored-together parameter flags for every command whose window covers `time`.
    private static func applyParameters(
        _ track: CommandTrack,
        at time: Double,
        zeroLengthEnd: Double,
        additive: inout Bool, flipH: inout Bool, flipV: inout Bool,
    ) {
        for command in track.commands {
            // Commands are sorted by startTime, so the rest start even later.
            if command.startTime > time { break }

            let effectiveEnd = command.startTime == command.endTime
                ? zeroLengthEnd
                : command.endTime
            if effectiveEnd < time { continue }

            guard case let .parameter(kind) = command.payload else { continue }
            switch kind {
            case .additive: additive = true
            case .flipHorizontal: flipH = true
            case .flipVertical: flipV = true
            }
        }
    }

    /// Eased interpolation over a command's window.
    ///
    /// Ported from `easedValue`.
    private static func eased(
        _ command: Command,
        _ time: Double,
        _ startValue: Double,
        _ endValue: Double,
    ) -> Double {
        let startTime = command.timing.startTime
        let endTime = command.timing.endTime

        if time < startTime { return startValue }
        if startTime == endTime { return endValue }

        let progress = Swift.min(1, (time - startTime) / (endTime - startTime))
        return easedLerp(startValue, endValue, progress, command.timing.easing)
    }
}

// ─── Sorting ─────────────────────────────────────────────────────────────────

extension Array where Element == Command {
    /// Sorts by start time, preserving the original order of equal elements.
    ///
    /// Swift's `sort` is not guaranteed stable, and the resolver's priority
    /// rules depend on file order for commands that start at the same time.
    mutating func stableSortByStartTime() {
        self = enumerated()
            .sorted { lhs, rhs in
                lhs.element.startTime == rhs.element.startTime
                    ? lhs.offset < rhs.offset
                    : lhs.element.startTime < rhs.element.startTime
            }
            .map(\.element)
    }
}
