import Foundation
import StoryboardCore
import Testing

/// Reading a `.srt` into the lines the lyrics panel places.
///
/// A subtitle file is somebody else's timing, done by hand — so the parser's job
/// is to keep it exactly, and to survive the shapes these files come in: a BOM,
/// Windows line endings, a dot where the format says comma, styling tags.
@Suite("Subtitle parsing")
struct SubtitleParserTests {
    @Test("each cue becomes a line at its own time")
    func readsCues() {
        let srt = """
        1
        00:00:16,680 --> 00:00:21,780
        落ちてゆく砂時計ばかり見てるよ

        2
        00:00:22,020 --> 00:00:27,360
        逆さまにすればほらまだ始まるよ

        """

        let lines = SubtitleParser.lines(from: srt)

        #expect(lines.map(\.text) == ["落ちてゆく砂時計ばかり見てるよ", "逆さまにすればほらまだ始まるよ"])
        #expect(lines.map(\.start) == [16_680, 22_020])
        #expect(lines.map(\.end) == [21_780, 27_360])
    }

    @Test("hours and minutes count")
    func readsHoursAndMinutes() throws {
        let lines = SubtitleParser.lines(from: "1\n01:02:03,004 --> 01:02:04,500\nhi\n")

        let line = try #require(lines.first)
        #expect(line.start == 3_723_004)
        #expect(line.end == 3_724_500)
    }

    @Test("a line from a subtitle file claims no confidence")
    func noConfidence() throws {
        // A confidence is a measurement, and nobody measured these: a default
        // would mark hand-timed lines as sure or unsure for no reason.
        let line = try #require(SubtitleParser.lines(from: "1\n00:00:01,000 --> 00:00:02,000\nhi\n").first)
        #expect(line.confidence == nil)
    }

    @Test("a BOM and Windows line endings do not lose the first cue")
    func survivesBOMAndCRLF() {
        let srt = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,000\r\none\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\ntwo\r\n"

        let lines = SubtitleParser.lines(from: srt)

        #expect(lines.map(\.text) == ["one", "two"])
        #expect(lines.map(\.start) == [1_000, 3_000])
    }

    @Test("a dot works where the format says comma")
    func acceptsDotMilliseconds() {
        let lines = SubtitleParser.lines(from: "1\n00:00:01.250 --> 00:00:02.500\nhi\n")
        #expect(lines.map(\.start) == [1_250])
        #expect(lines.map(\.end) == [2_500])
    }

    @Test("a cue on two rows stays one line with a break")
    func keepsMultilineCues() {
        let lines = SubtitleParser.lines(from: "1\n00:00:01,000 --> 00:00:02,000\nfirst row\nsecond row\n")
        #expect(lines.map(\.text) == ["first row\nsecond row"])
    }

    @Test("styling tags are dropped, the words are kept")
    func stripsTags() {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\n{\\an8}<i>so</i> <font color=\"#ff0000\">red</font>\n"
        #expect(SubtitleParser.lines(from: srt).map(\.text) == ["so red"])
    }

    @Test("a cue with no text is skipped")
    func skipsEmptyCues() {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\n<i></i>\n\n2\n00:00:03,000 --> 00:00:04,000\nhi\n"
        #expect(SubtitleParser.lines(from: srt).map(\.text) == ["hi"])
    }

    @Test("a cue that ends before it starts is skipped")
    func skipsBackwardsCues() {
        let srt = "1\n00:00:05,000 --> 00:00:04,000\nnope\n\n2\n00:00:06,000 --> 00:00:07,000\nyes\n"
        #expect(SubtitleParser.lines(from: srt).map(\.text) == ["yes"])
    }

    @Test("a missing blank line does not swallow the next cue's number")
    func toleratesMissingBlankLine() {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\none\n2\n00:00:03,000 --> 00:00:04,000\ntwo\n"
        #expect(SubtitleParser.lines(from: srt).map(\.text) == ["one", "two"])
    }

    @Test("a lyric that is only a number survives when the cue is separated")
    func keepsNumericLyric() {
        // The index-dropping above is only for text running into the next
        // timing line; a properly separated cue that says "3" means it.
        let srt = "1\n00:00:01,000 --> 00:00:02,000\n3\n\n2\n00:00:03,000 --> 00:00:04,000\ntwo\n"
        #expect(SubtitleParser.lines(from: srt).map(\.text) == ["3", "two"])
    }

    @Test("lines come out in time order")
    func sortsByStart() {
        let srt = "2\n00:00:03,000 --> 00:00:04,000\nlater\n\n1\n00:00:01,000 --> 00:00:02,000\nearlier\n"
        #expect(SubtitleParser.lines(from: srt).map(\.text) == ["earlier", "later"])
    }

    @Test("two cues starting together become one line")
    func mergesSameStart() throws {
        // A line is identified by its start: two sharing it would be one row in
        // the panel and one mark in what was placed. Two cues shown at the same
        // instant are on screen together anyway — a translation under the
        // original, usually.
        let srt = "1\n00:00:01,000 --> 00:00:02,000\noriginal\n\n2\n00:00:01,000 --> 00:00:03,000\ntranslation\n"

        let lines = SubtitleParser.lines(from: srt)

        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.text == "original\ntranslation")
        #expect(line.end == 3_000)
    }

    @Test("text that is not a subtitle file gives no lines")
    func rejectsNonsense() {
        #expect(SubtitleParser.lines(from: "just some notes\nwith no timing\n").isEmpty)
        #expect(SubtitleParser.lines(from: "").isEmpty)
    }

    // ─── Files timed word by word ────────────────────────────────────────────

    /// Karaoke-style files time every word as its own cue. Placed as they are,
    /// a song is three hundred clips of one word each.
    private static func cues(_ texts: [String], every step: Double = 400) -> String {
        texts.enumerated().map { index, text in
            let start = 10_000 + Double(index) * step
            return "\(index + 1)\n\(stamp(start)) --> \(stamp(start + step * 0.9))\n\(text)\n"
        }.joined(separator: "\n")
    }

    private static func stamp(_ ms: Double) -> String {
        let total = Int(ms)
        return String(
            format: "%02d:%02d:%02d,%03d",
            total / 3_600_000, total / 60_000 % 60, total / 1000 % 60, total % 1000,
        )
    }

    @Test("short cues are read as words")
    func detectsWordTiming() {
        let words = SubtitleParser.lines(from: Self.cues(["Time", "went", "by", "so", "quickly", "You", "were", "only"]))
        #expect(SubtitleParser.isTimedByWord(words))
    }

    @Test("sung lines are read as lines")
    func detectsLineTiming() {
        let lines = SubtitleParser.lines(from: Self.cues(["落ちてゆく砂時計", "逆さまにすれば", "刻んだだけ", "進む"], every: 4_000))
        #expect(!SubtitleParser.isTimedByWord(lines))
    }

    @Test("words keep the space a sentence needs, glyphs do not")
    func spacesWords() {
        let english = SubtitleParser.words(from: SubtitleParser.lines(from: Self.cues(["Time", "went", "by"])))
        #expect(LyricTranscription.lines(from: english).map(\.text) == ["Time went by"])

        let japanese = SubtitleParser.words(from: SubtitleParser.lines(from: Self.cues(["落", "ち", "て"])))
        #expect(LyricTranscription.lines(from: japanese).map(\.text) == ["落ちて"])
    }

    @Test("a word keeps the timing its cue gave it")
    func wordsKeepTiming() {
        let words = SubtitleParser.words(from: SubtitleParser.lines(from: Self.cues(["Time", "went"])))
        #expect(words.map(\.start) == [10_000, 10_400])
        #expect(words.map(\.end) == [10_360, 10_760])
        #expect(words.allSatisfy { $0.confidence == nil })
    }
}

