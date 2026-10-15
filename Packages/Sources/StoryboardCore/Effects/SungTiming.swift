import Foundation

/// When one word of a lyric clip was sung, in the clip's own time.
///
/// What turns a lyric clip into karaoke: a stagger says "one after another",
/// this says *when* — the moment the singer reached the word, which no stagger
/// can guess. Kept on the node, not derived from the song, because it came from
/// a transcription or a hand-timed `.srt` that the clip no longer has.
public struct SungWord: Codable, Sendable, Equatable {
    /// Milliseconds into the clip.
    public var start: Double
    public var end: Double
    /// How many glyphs of the clip's text this word covers: its characters
    /// that are not spacing.
    ///
    /// Counted in characters rather than matched to the layout's words,
    /// because the two disagree exactly where karaoke matters: a Japanese line
    /// has no spaces, so the layout sees one word, while the transcription
    /// timed it glyph by glyph.
    public var characters: Int

    public init(start: Double, end: Double, characters: Int) {
        self.start = start
        self.end = end
        self.characters = characters
    }
}

/// Mapping sung words onto a text clip's glyphs.
public enum SungTiming {
    /// The choice that makes a text clip read its sung timing — offered on
    /// `Stagger Mode` (words appear as sung) and `Sweep Order` (words light as
    /// sung).
    public static let choice = "Sung"

    /// A line's words, as timings local to a clip starting at `clipStart`.
    public static func words(from words: [LyricTranscription.Word], clipStart: Double) -> [SungWord] {
        words.compactMap { word in
            let characters = glyphCount(word.text)
            guard characters > 0 else { return nil }
            return SungWord(start: word.start - clipStart, end: word.end - clipStart, characters: characters)
        }
    }

    /// Whether the timings still describe `text`.
    ///
    /// By count: a typo fixed in place keeps every word on its moment, while a
    /// word added or removed would shift every later one onto the wrong glyph
    /// — and a karaoke that lights the wrong word is worse than none.
    public static func fits(_ sung: [SungWord], text: String) -> Bool {
        !sung.isEmpty && sung.reduce(0) { $0 + $1.characters } == glyphCount(text)
    }

    /// The glyphs a text clip draws: every character that is not spacing.
    static func glyphCount(_ text: String) -> Int {
        text.reduce(0) { $1.isWhitespace ? $0 : $0 + 1 }
    }

    /// When each glyph is reached, in reading order.
    ///
    /// - `Word`: the sung word's start, for all its glyphs.
    /// - `Character`: the glyphs spread across their word's own duration —
    ///   letter by letter as it is sung.
    /// - `Line`: the first sung moment on the line.
    static func glyphTimes(_ sung: [SungWord], unit: String, lines: [Int]) -> [Double] {
        var characterTimes: [Double] = []
        var wordTimes: [Double] = []
        for word in sung {
            let length = max(0, word.end - word.start)
            for index in 0..<word.characters {
                characterTimes.append(word.start + length * Double(index) / Double(word.characters))
                wordTimes.append(word.start)
            }
        }
        switch unit {
        case "Character":
            return characterTimes
        case "Line":
            var first: [Int: Double] = [:]
            for (time, line) in zip(wordTimes, lines) {
                first[line] = min(first[line] ?? time, time)
            }
            return lines.map { first[$0] ?? 0 }
        default:
            return wordTimes
        }
    }
}
