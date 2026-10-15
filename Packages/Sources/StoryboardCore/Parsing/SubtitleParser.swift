import Foundation

/// Reads a `.srt` into the lines the lyrics panel places.
///
/// The other way in to a lyric storyboard: a transcription guesses the timing,
/// a subtitle file is somebody's timing done by hand. So nothing here regroups
/// or retimes — each cue is a line, at exactly the moment the file says.
///
/// Lenient about the shapes these files really come in — a BOM, Windows line
/// endings, a dot where the format says comma, styling tags, a missing blank
/// line — because each of those is common, and a file that loads with a cue
/// missing is worse than one that refuses: nobody notices the gap until it is
/// in the storyboard.
public enum SubtitleParser {
    public static func lines(from text: String) -> [LyricTranscription.Line] {
        let rows = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var cues: [(start: Double, end: Double, text: [String])] = []
        var current: (start: Double, end: Double, text: [String])?

        func close() {
            if let cue = current { cues.append(cue) }
            current = nil
        }

        for raw in rows {
            let row = raw.trimmingCharacters(in: .whitespaces)

            if let timing = timing(row) {
                // A cue that runs straight into the next timing line, with no
                // blank between, has swallowed that cue's index number.
                if var cue = current, let last = cue.text.last, isIndex(last) {
                    cue.text.removeLast()
                    current = cue
                }
                close()
                current = (timing.start, timing.end, [])
                continue
            }

            if row.isEmpty {
                close()
                continue
            }

            // Outside a cue a row is an index, or something that is not a
            // subtitle at all; either way it is not text to show.
            current?.text.append(row)
        }
        close()

        // Merged by start, because a line is identified by its start: two
        // sharing one would be one row in the panel. Shown at the same instant
        // they are on screen together anyway — a translation under its line.
        var byStart: [Double: LyricTranscription.Line] = [:]
        for cue in cues where cue.end >= cue.start {
            let text = cue.text.map(stripTags).filter { !$0.isEmpty }.joined(separator: "\n")
            guard !text.isEmpty else { continue }

            if var line = byStart[cue.start] {
                line.text += "\n" + text
                line.end = max(line.end, cue.end)
                byStart[cue.start] = line
            } else {
                // No confidence: nobody measured these, and a default would mark
                // hand-timed lines as sure or unsure for no reason.
                byStart[cue.start] = LyricTranscription.Line(text: text, start: cue.start, end: cue.end)
            }
        }
        return byStart.values.sorted { $0.start < $1.start }
    }

    // ─── Files timed word by word ────────────────────────────────────────────

    /// Below this a typical cue is a word, not a line.
    ///
    /// Measured on a real karaoke-style file, words run 0.1–1.1 s with a
    /// median near 0.35; a sung line is seconds long even in a fast song.
    public static let wordCueDuration: Double = 1000

    /// Whether the cues are words rather than lines.
    ///
    /// Karaoke-style files time every word as its own cue, and placed as they
    /// are a song is three hundred one-word clips. Decided by the *median*
    /// cue, not any one: a held note makes a single word long, and a short
    /// interjection makes a single line short.
    public static func isTimedByWord(_ cues: [LyricTranscription.Line]) -> Bool {
        guard !cues.isEmpty else { return false }
        let durations = cues.map(\.duration).sorted()
        return durations[durations.count / 2] < wordCueDuration
    }

    /// The cues as words, ready for ``LyricTranscription/lines(from:gapThreshold:maximumDuration:)``.
    ///
    /// The grouper concatenates exactly what it is given, the way the speech
    /// engine hands words over — with the space *leading* each Latin word and
    /// none before a CJK glyph. So the space is put back here, where the cue
    /// boundary still says a word ended.
    public static func words(from cues: [LyricTranscription.Line]) -> [LyricTranscription.Word] {
        cues.map { cue in
            let text = cue.text.replacingOccurrences(of: "\n", with: " ")
            let spaced = text.unicodeScalars.first.map(isCJK) == true ? text : " " + text
            return LyricTranscription.Word(text: spaced, start: cue.start, end: cue.end)
        }
    }

    /// The same boundary vertical text uses: everything from the CJK radicals
    /// up has no spaces between its words.
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x2E80
    }

    // ─── Rows ────────────────────────────────────────────────────────────────

    /// `00:00:16,680 --> 00:00:21,780`, with anything after the end time (cue
    /// positions some tools write) ignored.
    private static func timing(_ row: String) -> (start: Double, end: Double)? {
        let sides = row.components(separatedBy: "-->")
        guard sides.count == 2 else { return nil }
        let endField = sides[1].trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        guard
            let start = timestamp(sides[0].trimmingCharacters(in: .whitespaces)),
            let end = timestamp(endField)
        else { return nil }
        return (start, end)
    }

    /// Milliseconds from `HH:MM:SS,mmm` (or `MM:SS.mmm`).
    private static func timestamp(_ field: String) -> Double? {
        let parts = field.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }

        var seconds = 0.0
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            // Only the seconds carry a fraction; whole fields elsewhere keep a
            // stray "1.5" from reading as a minute and a half.
            guard let value = isLast ? Double(part) : Int(part).map(Double.init), value >= 0 else {
                return nil
            }
            seconds = seconds * 60 + value
        }
        // Rounded to the millisecond the format carries: `0.001 * 1000` is not
        // exactly one in floating point.
        return (seconds * 1000).rounded()
    }

    private static func isIndex(_ row: String) -> Bool {
        !row.isEmpty && row.allSatisfy(\.isASCIIDigit)
    }

    /// Drops `<i>`, `<font …>` and `{\an8}`-style overrides, keeping the words.
    private static func stripTags(_ row: String) -> String {
        var out = ""
        var closing: Character?
        for character in row {
            if let end = closing {
                if character == end { closing = nil }
                continue
            }
            switch character {
            case "<": closing = ">"
            case "{": closing = "}"
            default: out.append(character)
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
