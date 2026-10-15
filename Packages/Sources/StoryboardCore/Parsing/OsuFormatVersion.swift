import Foundation

/// The format version an `.osu` file declares on its first line.
///
/// Needed because the game reads a beatmap's `.osb` with the version of the
/// `.osu` it belongs to, and some of its storyboard rules depend on it — old
/// animations play at a requantised frame delay. A `.osb` has no header of its
/// own, so this is the only place that number comes from.
public enum OsuFormatVersion {
    /// The `N` of `osu file format vN` on the first non-blank line, or `nil`
    /// when that line is not the header.
    ///
    /// Only the first line is looked at: the header is defined as the start of
    /// the file, and the words further down — in a comment, a title — say
    /// nothing about the format.
    public static func parse(_ source: String) -> Int? {
        let prefix = "osu file format v"
        let firstLine = source
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let firstLine, firstLine.hasPrefix(prefix) else { return nil }
        return Int(firstLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
    }
}
