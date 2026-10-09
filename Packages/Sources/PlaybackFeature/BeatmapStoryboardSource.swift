import Foundation
import StoryboardCore
import StoryboardPersistence

/// Plays the storyboard of a beatmap folder on disk.
public struct BeatmapStoryboardSource: StoryboardSource {
    public let displayName: String
    private let folder: BeatmapFolder
    private let sprites: [StoryboardSprite]

    /// Image paths the storyboard references that are not in the folder. Those
    /// sprites still animate, drawn as flat quads.
    public let missingImagePaths: Set<String>

    public let audioURL: URL?

    /// Timing and metadata from the beatmap's first readable `.osu`.
    public let timing: BeatmapTimingData?

    public let gameplayDifficulties: [GameplayDifficultyOption]
    public let defaultGameplayDifficultyPath: String?

    /// Told each time a difficulty's hit objects are parsed. `nil` in the app;
    /// a test counts with it to show that opening a folder parses none.
    private let onGameplayParse: (@Sendable () -> Void)?

    /// Loads the storyboard eagerly, so a broken folder fails here rather than
    /// mid-render.
    public init(folderURL: URL, onGameplayParse: (@Sendable () -> Void)? = nil) throws {
        let folder = try BeatmapFolder(url: folderURL)
        let loaded = try BeatmapStoryboardLoader.load(from: folder)

        self.folder = folder
        sprites = loaded.sprites
        missingImagePaths = Set(loaded.missingImagePaths)
        audioURL = loaded.audioURL
        timing = loaded.timing
        self.onGameplayParse = onGameplayParse
        gameplayDifficulties = loaded.difficulties.map { file in
            GameplayDifficultyOption(
                path: file.path,
                name: file.path == loaded.timingOsuPath ? "\(file.version) (timing)" : file.version,
            )
        }
        defaultGameplayDifficultyPath = loaded.timingOsuPath

        // Prefer the beatmap's own title over the folder name, which usually
        // carries a leading beatmap id.
        let title = loaded.timing?.metadata.displayName ?? ""
        displayName = title.isEmpty ? folder.name : title
    }

    public func loadSprites() throws -> [PreparedSprite] {
        StoryboardResolver.prepare(sprites)
    }

    /// Parsed on demand, from whichever difficulty the overlay asks for.
    public func loadGameplay(path: String) -> GameplayMap? {
        guard gameplayDifficulties.contains(where: { $0.path == path }),
              let data = folder.data(forRelativePath: path)
        else { return nil }
        onGameplayParse?()
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return GameplayMap(OsuGameplayParser.parse(text))
    }

    public func imageData(for filePath: String) -> Data? {
        folder.data(forRelativePath: filePath)
    }
}
