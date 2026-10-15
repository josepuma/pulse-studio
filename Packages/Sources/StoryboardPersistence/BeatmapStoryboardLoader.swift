import Foundation
import StoryboardCore

/// Loads a beatmap folder's storyboard.
///
/// A storyboard lives either in a standalone `.osb` or in the `[Events]`
/// section of a `.osu` difficulty. The shared `.osb` is read, and **one**
/// difficulty's events are laid on top of it — which is what osu! shows, since
/// only one difficulty is ever played at a time.
public enum BeatmapStoryboardLoader {
    /// A readable difficulty (`.osu`) of the folder.
    public struct DifficultyFile: Sendable, Equatable {
        /// Relative path inside the folder.
        public let path: String
        /// `[Metadata] Version`, or the file name without extension when the
        /// file does not name one.
        public let version: String
    }

    public struct Result: Sendable {
        /// Sprites ready for resolution, in draw order.
        public let sprites: [StoryboardSprite]
        /// Relative path of the `.osb`, when one was found.
        public let osbPath: String?
        /// Relative path of the difficulty whose events were used, when any
        /// difficulty had some. At most one.
        public let osuPaths: [String]
        /// Sprites whose image could not be found on disk.
        public let missingImagePaths: [String]
        /// The beatmap's own sounds: `Sample` lines from the `.osb` and from
        /// the difficulty whose events were used, in that order.
        ///
        /// Kept beside the sprites for the same reason as them: a sound
        /// effect written in the file is part of the storyboard, and dropping
        /// it here left the preview silent where the game plays it.
        public var samples: [StoryboardSample] = []
        /// Timing and metadata from the first `.osu` that parsed, when present.
        public let timing: BeatmapTimingData?
        /// The beatmap's audio file, resolved against the folder.
        public let audioURL: URL?

        /// Every readable difficulty, in loader order. Only listed here: nothing
        /// of their hit objects is parsed at load time.
        public let difficulties: [DifficultyFile]
        /// The difficulty `timing` came from: the first readable one, and the
        /// default for anything that needs "a" difficulty.
        public let timingOsuPath: String?

        /// `"<version> (timing)"` for the default difficulty, so a UI can say
        /// why it is the preselected one.
        public var timingDifficultyName: String? {
            difficulties.first { $0.path == timingOsuPath }.map { "\($0.version) (timing)" }
        }

        public var spriteCount: Int { sprites.count }
    }

    /// Reads and merges the folder's storyboard sources.
    ///
    /// - Throws: ``BeatmapFolderError/notABeatmapFolder(_:)`` when the folder
    ///   holds no difficulty, no audio and no storyboard.
    public static func load(from folder: BeatmapFolder) throws -> Result {
        var sprites: [StoryboardSprite] = []

        // The shared .osb draws first, beneath any difficulty-specific events.
        // Its sprites wait for a version: the game reads a `.osb` with the
        // version of the `.osu` it plays, and old maps' animations depend on it.
        let osbPath = folder.files(withExtensions: ["osb"]).first
        var osbSprites: [StoryboardSprite] = []
        var samples: [StoryboardSample] = []
        if let osbPath, let source = readText(at: osbPath, in: folder) {
            let parsed = OsbParser.parse(source)
            osbSprites = parsed.sprites
            samples = parsed.samples
        }
        var timingFormatVersion: Int?
        var timingSamples: [StoryboardSample] = []

        var contributingOsuPaths: [String] = []
        var timing: BeatmapTimingData?
        var timingOsuPath: String?
        var difficulties: [DifficultyFile] = []

        for osuPath in folder.files(withExtensions: ["osu"]) {
            guard let source = readText(at: osuPath, in: folder) else { continue }

            // Difficulties of one beatmap share their audio and tempo, so the
            // first readable file settles both.
            // The same test decides what counts as a readable difficulty, so
            // the list's first entry IS the timing source.
            let parsed = OsuParser.parse(source)
            if !parsed.audioFilename.isEmpty || !parsed.uninheritedPoints.isEmpty {
                let version = parsed.metadata.version
                difficulties.append(DifficultyFile(
                    path: osuPath,
                    version: version.isEmpty ? Self.fileStem(osuPath) : version,
                ))
                if timing == nil {
                    timing = parsed
                    timingOsuPath = osuPath
                    timingFormatVersion = OsuFormatVersion.parse(source)
                    timingSamples = OsbParser.parse(source).samples
                }
            }

            // One difficulty's events, not every difficulty's.
            //
            // osu! plays a single difficulty at a time: its own events draw on
            // top of the shared `.osb`, and the other difficulties' are not
            // there at all. Merging them all stacks the same sprite over itself
            // once per difficulty — four copies of a semi-transparent PNG read
            // as one far more saturated than the file, which is only visible on
            // the sprites a mapper happened to put in the `.osu`.
            guard contributingOsuPaths.isEmpty else { continue }

            let parsedEvents = OsbParser.parse(source)
            let parsedSprites = parsedEvents.sprites
            // Which difficulty is played is still decided by its sprites: a
            // file with only sounds must not take the place of the one that
            // draws. Its sounds come along with it.
            guard !parsedSprites.isEmpty else { continue }
            contributingOsuPaths.append(osuPath)
            samples.append(contentsOf: parsedEvents.samples)
            sprites.append(contentsOf: Self.playing(parsedSprites, formatVersion: OsuFormatVersion.parse(source)))
        }

        // No difficulty draws anything: the one that gives the timing is the
        // one played, so its sounds are the ones heard.
        if contributingOsuPaths.isEmpty { samples.append(contentsOf: timingSamples) }

        // The difficulty that gives the timing is the one played, so its
        // version is the one the shared `.osb` is read with.
        sprites.insert(contentsOf: Self.playing(osbSprites, formatVersion: timingFormatVersion), at: 0)

        // An empty storyboard is a starting point, not a failure. A folder with
        // audio and a difficulty is exactly what someone opens to write a
        // storyboard that does not exist yet — refusing it would mean the
        // editor could only ever open work that had already been done
        // elsewhere.
        //
        // What is still refused is a folder with nothing to build against: no
        // difficulty, no audio, no storyboard. That is not an empty project,
        // it is the wrong folder.
        guard !sprites.isEmpty || timing != nil || hasAudio(in: folder) else {
            throw BeatmapFolderError.notABeatmapFolder(folder.name)
        }

        // Parsers number sprites per file, so ids collide once files are merged.
        sprites = sprites.enumerated().map { index, sprite in
            var renumbered = sprite
            renumbered.id = "sprite_\(index)"
            return renumbered
        }

        let missing = Set(sprites.flatMap(AnimationFrames.paths(of:)))
            .filter { folder.fileURL(forRelativePath: $0) == nil }
            .sorted()

        // Fall back to scanning for an audio file: some folders name one the
        // `.osu` does not, or have no readable `.osu` at all.
        let audioURL = timing
            .map(\.audioFilename)
            .flatMap { folder.fileURL(forRelativePath: $0) }
            ?? firstAudioURL(in: folder)

        var result = Result(
            sprites: sprites,
            osbPath: osbPath,
            osuPaths: contributingOsuPaths,
            missingImagePaths: missing,
            timing: timing,
            audioURL: audioURL,
            difficulties: difficulties,
            timingOsuPath: timingOsuPath,
        )
        result.samples = samples
        return result
    }

    /// Sprites with each animation set to the delay the game plays for a file
    /// of this version. The written delay is kept for the round-trip.
    private static func playing(_ sprites: [StoryboardSprite], formatVersion: Int?) -> [StoryboardSprite] {
        sprites.map { sprite in
            guard var animation = sprite.animation else { return sprite }
            let delay = AnimationFrames.playbackDelay(animation.frameDelay, formatVersion: formatVersion)
            animation.playbackFrameDelay = delay == animation.frameDelay ? nil : delay
            var playing = sprite
            playing.animation = animation
            return playing
        }
    }

    private static func fileStem(_ path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard let dot = name.lastIndex(of: ".") else { return name }
        return String(name[..<dot])
    }

    /// Audio file extensions a beatmap folder may use.
    private static let audioExtensions = ["mp3", "ogg", "wav", "m4a"]

    private static func firstAudioURL(in folder: BeatmapFolder) -> URL? {
        folder.files(withExtensions: audioExtensions)
            .first
            .flatMap { folder.fileURL(forRelativePath: $0) }
    }

    private static func hasAudio(in folder: BeatmapFolder) -> Bool {
        !folder.files(withExtensions: audioExtensions).isEmpty
    }

    /// Reads a text file, falling back to Latin-1 for the older beatmaps that
    /// are not valid UTF-8.
    private static func readText(at relativePath: String, in folder: BeatmapFolder) -> String? {
        guard let data = folder.data(forRelativePath: relativePath) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }
}
