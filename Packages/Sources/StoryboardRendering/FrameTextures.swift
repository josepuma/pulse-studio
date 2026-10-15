import CoreGraphics
import Foundation
import ImageIO
import StoryboardCore
import UniformTypeIdentifiers

/// Which atlas entry an animated sprite draws, and which files the atlas holds.
///
/// Kept apart from the renderer and free of Metal so CI, which has no GPU, can
/// still check the choices that decide what ends up on screen.
enum FrameTextures {
    /// What a sprite draws this frame.
    enum Draw<Entry> {
        /// Its own image.
        case texture(Entry)
        /// A flat grey quad: a plain sprite whose file is missing, kept visible
        /// so a broken path is seen rather than silently absent.
        case placeholder
        /// Nothing: a missing frame of an animation. The frames around it are
        /// there, so a quad flashing once per cycle would be the loudest thing
        /// on screen for the smallest problem — and the game most likely draws
        /// nothing for a texture it could not load. The loader still reports
        /// the file.
        case nothing
    }

    /// The decision for a sprite at a frame.
    ///
    /// The one rule every caller shares: without an entry, nothing may sample
    /// the atlas. The fallback used to be slice 0 with the full UV rectangle,
    /// which drew a whole atlas page of other sprites squeezed into the quad.
    static func draw<Entry>(
        for sprite: PreparedSprite,
        frameIndex: Int,
        in entries: [String: Entry],
    ) -> Draw<Entry> {
        if let entry = entry(for: sprite, frameIndex: frameIndex, in: entries) {
            return .texture(entry)
        }
        return sprite.animation == nil ? .placeholder : .nothing
    }

    /// The atlas key of the placeholder's image.
    ///
    /// Prefixed like the other app-made images (`__builtin__`, `__derived__`,
    /// `__text__`), so no path from a beatmap can name it.
    static let placeholderPath = "__placeholder__/missing.png"

    /// The size a placeholder quad is drawn at, in storyboard units.
    static let placeholderSize = SIMD2<Float>(100, 100)

    /// A small opaque mid-grey PNG.
    ///
    /// Grey rather than white so it reads on a black stage and on a white
    /// background alike; the sprite's own tint still multiplies it, which is
    /// what a quad standing in for an image should do.
    static let placeholderImage: Data = {
        let side = 4
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = 128
            pixels[offset + 1] = 128
            pixels[offset + 2] = 128
            pixels[offset + 3] = 255
        }
        let data = NSMutableData()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent,
              ),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }()

    /// The file drawn for a sprite at a frame.
    static func path(for sprite: PreparedSprite, frameIndex: Int) -> String {
        sprite.texturePath(frameIndex: frameIndex)
    }

    /// The atlas entry for the current frame. Each frame has its own, so its
    /// pixel size and alpha mask are the frame's own and not the first one's.
    /// `nil` is a missing image; ``draw(for:frameIndex:in:)`` says what to do.
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

extension FrameTextures.Draw: Equatable where Entry: Equatable {}
