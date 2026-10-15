import StoryboardCore

/// Which atlas entry an animated sprite draws, and which files the atlas holds.
///
/// Kept apart from the renderer and free of Metal so CI, which has no GPU, can
/// still check the choices that decide what ends up on screen.
enum FrameTextures {
    /// The file drawn for a sprite at a frame.
    static func path(for sprite: PreparedSprite, frameIndex: Int) -> String {
        sprite.texturePath(frameIndex: frameIndex)
    }

    /// The atlas entry for the current frame. Each frame has its own, so its
    /// pixel size and alpha mask are the frame's own and not the first one's.
    /// `nil` is a missing image, drawn as a flat quad.
    static func entry<Entry>(
        for sprite: PreparedSprite,
        frameIndex: Int,
        in entries: [String: Entry],
    ) -> Entry? {
        entries[sprite.texturePath(frameIndex: frameIndex)]
    }

    /// Every file the atlas must hold, sorted and without repeats. Sorted so
    /// "did the set change" is a plain comparison.
    static func atlasPaths(for sprites: [PreparedSprite]) -> [String] {
        var seen = Set<String>()
        for sprite in sprites {
            for path in sprite.texturePaths { seen.insert(path) }
        }
        return seen.sorted()
    }
}
