import Foundation

/// A parsed difficulty ready to be drawn: placed objects, their time index and
/// a lazy cache of slider geometry.
///
/// Nothing heavy happens at init beyond one pass over the objects: slider
/// paths and meshes are built the first time an object is asked for and kept
/// (bounded by ``meshCacheCapacity``). A new difficulty is a new map, so the
/// cache is never stale.
public final class GameplayMap: @unchecked Sendable {
    /// How long an object keeps fading after its hit.
    public static let fadeOut: Double = 240
    public static let meshCacheCapacity = 512

    public let difficulty: BeatmapDifficulty
    public let comboColours: [ComboColour]
    public let objects: [PlacedObject]
    public let index: GameplayIndex
    /// The kiai star fountains, a pure function of time.
    public let fountains: KiaiFountains

    private struct Entry {
        let path: SliderPath
        var mesh: [SliderMeshVertex]?
    }

    private let lock = NSLock()
    private var cache: [Int: Entry] = [:]
    private var builds = 0

    public init(_ gameplay: BeatmapGameplay) {
        difficulty = gameplay.difficulty
        comboColours = gameplay.comboColours
        fountains = KiaiFountains(starts: gameplay.kiaiStarts)
        let radius = BeatmapDifficultyMath.radius(cs: gameplay.difficulty.cs)
        let preempt = BeatmapDifficultyMath.preempt(ar: gameplay.difficulty.ar)
        objects = gameplay.hitObjects.enumerated().map { position, object in
            var end = object.time
            var span = 0.0
            switch object.kind {
            case .circle:
                break
            case let .slider(slider):
                end = SliderTiming.endTime(
                    of: slider, startTime: object.time,
                    difficulty: gameplay.difficulty, controlPoints: gameplay.controlPoints,
                )
                span = SliderTiming.spanDuration(
                    pixelLength: slider.pixelLength,
                    sv: gameplay.controlPoints.sv(at: object.time),
                    multiplier: gameplay.difficulty.sliderMultiplier,
                    beatLength: gameplay.controlPoints.beatLength(at: object.time),
                )
            case let .spinner(endTime):
                end = max(endTime, object.time)
            }
            return PlacedObject(
                index: position, object: object, endTime: end, spanDuration: span,
                radius: radius, preempt: preempt,
            )
        }
        index = GameplayIndex(objects)
    }

    public func comboColour(of placed: PlacedObject) -> ComboColour {
        ComboColour.pick(from: comboColours, indexWithOffsets: placed.object.comboIndexWithOffsets)
    }

    /// How many slider bodies were tessellated so far (a probe for tests).
    public var meshBuildCount: Int { lock.withLock { builds } }
    public var cachedMeshCount: Int { lock.withLock { cache.count } }

    /// The slider's path, built on first use. `nil` for other kinds.
    public func path(forObject position: Int, at time: Double = 0) -> SliderPath? {
        entry(position, at: time)?.path
    }

    /// The slider body in STORYBOARD space (mapped once, here), built on first
    /// use and cached. `time` is "now": when the cache is full it decides what
    /// is farthest away.
    public func mesh(forObject position: Int, at time: Double) -> [SliderMeshVertex]? {
        guard objects.indices.contains(position), case .slider = objects[position].object.kind else { return nil }
        return lock.withLock {
            let entry = ensureEntry(position, at: time)
            if let mesh = entry?.mesh { return mesh }
            guard let entry else { return nil }
            let placed = objects[position]
            let mesh = SliderMesh.build(
                entry.path, radius: placed.radius, maxVertices: SliderMesh.defaultMaxVertices,
                translatedBy: PlayfieldMapping.offset,
            )
            builds += 1
            cache[position]?.mesh = mesh
            return mesh
        }
    }

    private func entry(_ position: Int, at time: Double) -> Entry? {
        guard objects.indices.contains(position), case .slider = objects[position].object.kind else { return nil }
        return lock.withLock { ensureEntry(position, at: time) }
    }

    /// Caller holds the lock.
    private func ensureEntry(_ position: Int, at time: Double) -> Entry? {
        if let hit = cache[position] { return hit }
        guard case let .slider(slider) = objects[position].object.kind else { return nil }
        if cache.count >= Self.meshCacheCapacity { evict(at: time) }
        let entry = Entry(path: SliderPath(slider: slider, head: objects[position].object.position), mesh: nil)
        cache[position] = entry
        return entry
    }

    /// Drops the entry farthest from `time`, preferring one that is not
    /// visible. Visible entries are only dropped when EVERY entry is visible:
    /// the cap is a hard bound against hostile maps, not a hint.
    private func evict(at time: Double) {
        func distance(_ position: Int) -> Double {
            let placed = objects[position]
            return abs(placed.object.time - (time.isFinite ? time : 0))
        }
        let hidden = cache.keys.filter { !objects[$0].isVisible(at: time) }
        let pool = hidden.isEmpty ? Array(cache.keys) : hidden
        if let victim = pool.max(by: { distance($0) < distance($1) }) { cache[victim] = nil }
    }
}
