import Foundation
import StoryboardCore

/// Writes a storyboard and everything it needs to draw.
///
/// A `.osb` is only half a storyboard: it names images, and the ones this app
/// provides — the built-in shapes, the bundled particles, the blurred copies a
/// glow derives — live inside the binary, where the game cannot reach them. So
/// exporting is two jobs. The file is written, and every image it names that
/// is not already the mapper's own is written beside it under a path the file
/// then points at.
public enum StoryboardExport {
    /// Where generated images go, relative to the beatmap folder.
    ///
    /// Under `sb/` because that is where storyboard art conventionally lives,
    /// and in a folder of its own so it is obvious which files the editor made
    /// and which the mapper drew — deleting the folder cannot destroy anyone's
    /// artwork.
    public static let generatedFolder = "sb/_generated"

    public struct Result: Sendable {
        /// The storyboard text, ready to write.
        public let storyboard: String
        /// Generated images, keyed by their path relative to the folder.
        public let images: [String: Data]
        /// Sample audio, keyed by the path the `Sample` line names. Only files
        /// that could be read: an unreadable one keeps its line and is the
        /// mapper's to find, as a missing image is.
        public let audio: [String: Data]
    }

    /// The extensions osu! plays as a sample.
    static let sampleExtensions: Set<String> = ["wav", "ogg", "mp3"]

    /// Resolves `path` beneath `directory`, or `nil` if it would land anywhere
    /// else.
    ///
    /// A path in a `.osb` is somebody else's input. Backslashes are Windows
    /// separators and are mapped first — otherwise `..\x` would slip past a
    /// check that only knows `/`. Absolute paths and any `..` component are
    /// refused outright, then the standardized result must sit under the
    /// directory **on a directory boundary**: a bare string prefix would let
    /// `export-evil/` pass for `export`.
    static func contained(_ path: String, in directory: URL) -> URL? {
        let normalised = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalised.isEmpty, !normalised.hasPrefix("/") else { return nil }
        let components = normalised.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty, !components.contains("..") else { return nil }

        let root = directory.standardizedFileURL
        let destination = root.appendingPathComponent(normalised).standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard destination.path.hasPrefix(prefix) else { return nil }
        return destination
    }

    private static func isSampleFile(_ path: String) -> Bool {
        guard let dot = path.lastIndex(of: ".") else { return false }
        return sampleExtensions.contains(path[path.index(after: dot)...].lowercased())
    }

    /// Prepares a storyboard for a folder, rewriting paths as it goes.
    ///
    /// - Parameter imageData: supplies the bytes for any path a sprite names,
    ///   the beatmap's own files included, or `nil` for one that cannot be
    ///   found. Passed in rather than reached for so this stays testable
    ///   without a beatmap on disk.
    /// Prepares an export using the images the app itself provides.
    ///
    /// A separate name rather than a defaulted overload: two `prepare` methods
    /// whose only difference is an argument label look identical at the call
    /// site, and this one resolved to itself — infinite recursion that took the
    /// test process down with it.
    public static func prepareUsingAppImages(
        _ sprites: [StoryboardSprite],
        samples: [StoryboardSample] = [],
        beatmapImage: @escaping (String) -> Data? = { _ in nil },
        beatmapAudio: @escaping (String) -> Data? = { _ in nil },
    ) -> Result {
        prepare(
            sprites,
            samples: samples,
            imageData: { appImageData(for: $0, beatmapImage: beatmapImage) },
            audioData: beatmapAudio,
        )
    }

    public static func prepare(
        _ sprites: [StoryboardSprite],
        samples: [StoryboardSample] = [],
        imageData: (String) -> Data?,
        audioData: (String) -> Data? = { _ in nil },
    ) -> Result {
        var images: [String: Data] = [:]
        var rewritten: [String: String] = [:]

        var prepared = sprites
        for index in prepared.indices {
            let original = prepared[index].filePath

            // An animation's base path is not an image: its frames are, and
            // they keep the mapper's own names so the line still derives them.
            // Rewriting the base would break that derivation, so it is left
            // exactly as named. Generated (built-in/derived/text) animations
            // have no files to ship and stay as named too.
            if prepared[index].animation != nil {
                for frame in AnimationFrames.paths(of: prepared[index]) {
                    guard images[frame] == nil,
                          !needsGenerating(frame),
                          // Checked per frame, not just on the base: every
                          // derived path is judged on its own.
                          isContainedRelative(frame),
                          let data = imageData(frame)
                    else { continue }
                    images[frame] = data
                }
                continue
            }

            // Each distinct path is generated once however many sprites name
            // it: an emitter points a thousand particles at one image.
            if let already = rewritten[original] {
                prepared[index].filePath = already
                continue
            }

            // A path that climbs out of the folder is never read, and is left
            // as it is: the writer refuses it too, and rewriting it would
            // hide that the file was skipped.
            guard needsGenerating(original) || isContainedRelative(original),
                  let data = imageData(original)
            else { continue }

            // A generated image has no path of its own, so it is given one. The
            // beatmap's own files keep theirs exactly: the export is meant to
            // drop onto the folder it came from, and a rewritten path would
            // stop matching the file already sitting there.
            let path = needsGenerating(original)
                ? "\(generatedFolder)/\(fileName(for: original))"
                : original

            images[path] = data
            rewritten[original] = path
            prepared[index].filePath = path
        }

        // Normalised here, after the paths are settled and before the text is
        // written: every sprite the export ships passes through this one point,
        // whichever effect, filter or script produced it, so the file and the
        // canvas cannot disagree about a sprite that only one source touched.
        // Samples: only audio files whose path stays inside the folder get a
        // line. A readable one is carried once however many lines name it.
        var audio: [String: Data] = [:]
        var lines: [StoryboardSample] = []
        for sample in samples where isSampleFile(sample.path) && isContainedRelative(sample.path) {
            lines.append(sample)
            if audio[sample.path] == nil, let data = audioData(sample.path) {
                audio[sample.path] = data
            }
        }

        return Result(
            storyboard: OsbWriter.write(OsbExportNormalization.normalize(prepared), samples: lines),
            images: images,
            audio: audio,
        )
    }

    /// Resolves the images the app itself provides.
    ///
    /// The default the app uses: built-in shapes and bundled particles come out
    /// of the bundle, and a derived path is generated from whatever it names —
    /// which may itself be a built-in, so this recurses. A path this cannot
    /// answer for belongs to the beatmap and is left where it is.
    static func appImageData(for path: String, beatmapImage: (String) -> Data?) -> Data? {
        if DerivedSprite.isDerived(path) {
            return DerivedTextures.data(for: path) { source in
                appImageData(for: source, beatmapImage: beatmapImage)
            }
        }
        // The beatmap's own files come last, so a built-in cannot be shadowed
        // by a file that happens to share its name.
        return TextTextures.data(for: path)
            ?? BuiltInTextures.data(for: path)
            ?? beatmapImage(path)
    }

    private static func isContainedRelative(_ path: String) -> Bool {
        contained(path, in: URL(fileURLWithPath: "/export-root", isDirectory: true)) != nil
    }

    /// Whether a path names an image the app provides rather than a file the
    /// beatmap already has.
    private static func needsGenerating(_ path: String) -> Bool {
        DerivedSprite.isDerived(path)
            || BuiltInTextures.isBuiltIn(path)
            || TextSprite.isText(path)
    }

    /// A flat, safe file name for a generated path.
    ///
    /// Derived paths carry the source inside them
    /// (`__derived__/blur12/sb/particle.png`), so the separators are folded
    /// into the name instead of becoming folders no one asked for. The result
    /// stays readable, which matters when someone opens the folder wondering
    /// what these files are.
    static func fileName(for path: String) -> String {
        var name = path
        for prefix in ["__derived__/", "__builtin__/", TextSprite.prefix]
            where name.hasPrefix(prefix)
        {
            name.removeFirst(prefix.count)
        }
        let cleaned = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        // Always a PNG: everything generated here is written as one, whatever
        // the source file was.
        return cleaned.hasSuffix(".png") ? cleaned : cleaned + ".png"
    }
}

public extension StoryboardExport {
    /// Writes an export into a folder of its own inside the beatmap.
    ///
    /// Laid out exactly as it would sit in the beatmap folder — the `.osb` at
    /// the top, generated images under `sb/_generated/` — so the whole folder
    /// can be dropped in place and the paths inside the file still resolve. A
    /// storyboard tested from somewhere else is not the storyboard that ships.
    ///
    /// - Returns: the folder written to.
    @discardableResult
    static func write(
        _ result: Result,
        toFolder folder: URL,
        named name: String,
    ) throws -> URL {
        let export = folder.appendingPathComponent("export", isDirectory: true)

        // Replaced wholesale rather than merged: files left from a previous
        // export are images nothing points at any more, and an emitter renamed
        // between runs would leave the old one sitting there looking current.
        if FileManager.default.fileExists(atPath: export.path) {
            try FileManager.default.removeItem(at: export)
        }
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)

        // Images and sample audio alike: both names come from a file someone
        // else wrote. A path that would land outside `export/` is skipped, not
        // an abort — the rest of the export is still good.
        for (path, data) in result.images.merging(result.audio, uniquingKeysWith: { first, _ in first }) {
            guard let destination = contained(path, in: export) else { continue }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try data.write(to: destination)
        }

        try result.storyboard.write(
            to: export.appendingPathComponent("\(name).osb"),
            atomically: true,
            encoding: .utf8,
        )

        return export
    }
}
