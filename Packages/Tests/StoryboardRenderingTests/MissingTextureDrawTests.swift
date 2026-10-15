import CoreGraphics
import Foundation
import ImageIO
import Testing

import StoryboardCore
@testable import StoryboardRendering

/// What a sprite draws when its image is not in the atlas.
///
/// Reported against a real map: an animation with one missing frame flashed a
/// square holding a whole atlas page of other sprites. With no entry the quad
/// fell back to slice 0 and the full UV rectangle — it never was the "flat
/// quad" the comments promised. Without an entry nothing may sample the atlas.
@Suite("Missing texture draw")
struct MissingTextureDrawTests {
    private func prepared(animation: SpriteAnimation?) -> PreparedSprite {
        let sprite = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre, filePath: "sb/a.png",
            defaultX: 0, defaultY: 0,
            commands: [Command(easing: .linear, startTime: 0, endTime: 1000, payload: .fade(start: 1, end: 1))],
            animation: animation,
        )
        return StoryboardResolver.prepare([sprite])[0]
    }

    private let animation = SpriteAnimation(frameCount: 3, frameDelay: 100, loopType: .loopForever)

    @Test("a frame that loaded draws its own texture")
    func loadedFrame() {
        let draw = FrameTextures.draw(for: prepared(animation: animation), frameIndex: 1, in: ["sb/a1.png": 7])
        #expect(draw == .texture(7))
    }

    @Test("a missing animation frame draws nothing")
    func missingFrameDrawsNothing() {
        // The frame before and after it are there: only this one is absent.
        let entries = ["sb/a0.png": 1, "sb/a2.png": 3]
        let draw = FrameTextures.draw(for: prepared(animation: animation), frameIndex: 1, in: entries)
        #expect(draw == .nothing)
    }

    @Test("a plain sprite with no image draws the placeholder")
    func missingPlainDrawsPlaceholder() {
        let draw = FrameTextures.draw(for: prepared(animation: nil), frameIndex: 0, in: [String: Int]())
        #expect(draw == .placeholder)
    }

    @Test("a plain sprite whose image loaded draws it")
    func loadedPlain() {
        let draw = FrameTextures.draw(for: prepared(animation: nil), frameIndex: 0, in: ["sb/a.png": 2])
        #expect(draw == .texture(2))
    }

    @Test("the placeholder is a solid opaque grey image, so the quad is flat")
    func placeholderImage() throws {
        let data = FrameTextures.placeholderImage
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            )
        })
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let first = Array(pixels[0..<4])
        #expect(first[3] == 255, "opaque")
        #expect(first[0] == first[1] && first[1] == first[2], "grey")
        #expect(first[0] > 40 && first[0] < 215, "readable on black and on white")
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            #expect(Array(pixels[offset..<offset + 4]) == first, "flat")
        }
    }

    @Test("the placeholder's key can never collide with a beatmap file")
    func placeholderKey() {
        // A path from a .osb is relative and never starts with "__" here: the
        // built-in, derived and text prefixes share that convention.
        #expect(FrameTextures.placeholderPath.hasPrefix("__"))
        #expect(!FrameTextures.atlasPaths(for: [prepared(animation: nil)]).contains(FrameTextures.placeholderPath))
    }
}
