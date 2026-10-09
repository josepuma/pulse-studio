import MetalKit
import StoryboardCore

/// Supplies a storyboard and its images to the playback feature.
///
/// The feature never reaches for a file system or a demo generator itself:
/// whoever composes the app decides where content comes from. That keeps
/// playback testable and lets the development harness feed it a generated
/// storyboard while the shipping app feeds it a beatmap folder.
public protocol StoryboardSource: Sendable {
    /// Name shown in the UI.
    var displayName: String { get }

    /// The track to play alongside the storyboard, when there is one.
    ///
    /// A source without audio plays against a synthetic clock instead.
    var audioURL: URL? { get }

    /// Tempo, kiai and breaks, when the source knows them. Without this the
    /// timeline still scrubs, just with no beat grid.
    var timing: BeatmapTimingData? { get }

    /// Image paths the storyboard references but the source cannot supply.
    var missingImagePaths: Set<String> { get }

    /// Loads the storyboard's sprites, ready for resolution.
    func loadSprites() throws -> [PreparedSprite]

    /// Image data for a sprite's file path, or `nil` when it cannot be found —
    /// such sprites are drawn as flat quads rather than failing the load.
    func imageData(for filePath: String) -> Data?

    /// The difficulties whose hit objects the editor can overlay. Names only:
    /// listing them parses nothing, so a project that never turns the overlay
    /// on never pays for a hit object.
    var gameplayDifficulties: [GameplayDifficultyOption] { get }

    /// The difficulty the overlay starts on, one of `gameplayDifficulties`.
    var defaultGameplayDifficultyPath: String? { get }

    /// Parses one difficulty's hit objects into something drawable.
    ///
    /// Synchronous and `Sendable`-friendly on purpose: the model calls it from
    /// a detached task, never from the main actor.
    func loadGameplay(path: String) -> GameplayMap?
}

/// A difficulty the gameplay overlay can show.
public struct GameplayDifficultyOption: Sendable, Equatable, Hashable {
    /// Where the `.osu` lives, relative to the beatmap folder.
    public let path: String
    /// What the picker says. The one that supplies the beatmap's timing is
    /// named as such, so it is clear why it is the preselected one.
    public let name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

public extension StoryboardSource {
    /// Sources with no audio opt out by inheriting this.
    var audioURL: URL? { nil }
    /// Sources with no beatmap timing opt out by inheriting this.
    var timing: BeatmapTimingData? { nil }
    /// Sources that can supply every image opt out by inheriting this.
    var missingImagePaths: Set<String> { [] }
    /// Sources with no hit objects to show opt out by inheriting these.
    var gameplayDifficulties: [GameplayDifficultyOption] { [] }
    var defaultGameplayDifficultyPath: String? { nil }
    func loadGameplay(path: String) -> GameplayMap? { nil }
}

/// A source backed by `.osb` text already in memory.
public struct InMemoryStoryboardSource: StoryboardSource {
    public let displayName: String
    private let osb: String
    private let images: @Sendable (String) -> Data?

    public init(
        displayName: String,
        osb: String,
        images: @escaping @Sendable (String) -> Data?,
    ) {
        self.displayName = displayName
        self.osb = osb
        self.images = images
    }

    public func loadSprites() throws -> [PreparedSprite] {
        StoryboardResolver.prepare(OsbParser.parse(osb).sprites)
    }

    public func imageData(for filePath: String) -> Data? {
        images(filePath)
    }
}
