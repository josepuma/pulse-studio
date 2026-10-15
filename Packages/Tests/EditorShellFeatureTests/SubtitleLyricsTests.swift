import UniformTypeIdentifiers
import Foundation
import StoryboardCore
import Testing

@testable import EditorShellFeature

/// Bringing hand-timed lyrics in from a `.srt`.
///
/// The lines land where a transcription's would — the same list, the same
/// presets, the same placing — so what is tested here is only what differs:
/// where they came from, and that nothing retimes them.
@MainActor
@Suite("Lyrics from a subtitle file")
struct SubtitleLyricsTests {
    private static let srt = """
    1
    00:00:01,000 --> 00:00:02,500
    first

    2
    00:00:03,000 --> 00:00:04,000
    second

    """

    private static func file(_ contents: String, name: String = "song.srt") throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("srt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test("the cues become the panel's lines")
    func loadsLines() throws {
        let shell = EditorShellModel()

        shell.loadSubtitles(from: try Self.file(Self.srt))

        #expect(shell.lyricLines.map(\.text) == ["first", "second"])
        #expect(shell.lyricLines.map(\.start) == [1_000, 3_000])
        #expect(shell.lyricSource == .subtitles(name: "song.srt", byWord: false))
        #expect(shell.lyricError == nil)
    }

    @Test("regrouping does not retime a subtitle file")
    func regroupKeepsTiming() throws {
        // Its timing is the author's, done by hand: the grouping knobs exist to
        // fix a machine's guesses, and here there is nothing to fix.
        let shell = EditorShellModel()
        shell.loadSubtitles(from: try Self.file(Self.srt))

        shell.regroupLyrics(gapThreshold: 2_000)

        #expect(shell.lyricLines.map(\.text) == ["first", "second"])
    }

    @Test("placing them keeps the file's timing")
    func placesAtFileTiming() throws {
        let shell = EditorShellModel()
        shell.loadSubtitles(from: try Self.file(Self.srt))

        shell.importLyrics(shell.lyricLines, preset: TextEffect.presets.first)

        #expect(shell.effects.nodes.map(\.startTime) == [1_000, 3_000])
        #expect(shell.effects.nodes.map(\.duration) == [1_500, 1_000])
    }

    @Test("a file with no cues says so instead of showing nothing")
    func reportsEmptyFile() throws {
        let shell = EditorShellModel()

        shell.loadSubtitles(from: try Self.file("no timing here", name: "notes.srt"))

        #expect(shell.lyricLines.isEmpty)
        #expect(shell.lyricError != nil)
    }

    @Test("a failed load keeps the lines already there")
    func failedLoadKeepsLines() throws {
        // Picking the wrong file is a slip; it should not cost the draft
        // somebody was working through.
        let shell = EditorShellModel()
        shell.loadSubtitles(from: try Self.file(Self.srt))

        shell.loadSubtitles(from: try Self.file("nothing", name: "wrong.srt"))

        #expect(shell.lyricLines.map(\.text) == ["first", "second"])
        #expect(shell.lyricError != nil)
    }

    @Test("a file that is too large is refused before it is read")
    func refusesHugeFile() throws {
        let shell = EditorShellModel()
        let huge = String(repeating: "a", count: EditorShellModel.maximumSubtitleBytes + 1)

        shell.loadSubtitles(from: try Self.file(huge))

        #expect(shell.lyricLines.isEmpty)
        #expect(shell.lyricError != nil)
    }

    @Test("a Latin-1 file still reads")
    func readsLegacyEncoding() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("srt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("old.srt")
        let text = "1\n00:00:01,000 --> 00:00:02,000\ncanción\n"
        try #require(text.data(using: .windowsCP1252)).write(to: url)
        let shell = EditorShellModel()

        shell.loadSubtitles(from: url)

        #expect(shell.lyricLines.map(\.text) == ["canción"])
    }

    @Test("placed marks are cleared by a new file")
    func clearsPlacedMarks() throws {
        let shell = EditorShellModel()
        shell.loadSubtitles(from: try Self.file(Self.srt))
        shell.importLyricLine(shell.lyricLines[0])

        shell.loadSubtitles(from: try Self.file(Self.srt, name: "other.srt"))

        #expect(shell.placedLyricLines.isEmpty)
    }

    @Test("discarding forgets where the lines came from")
    func clearForgetsSource() throws {
        let shell = EditorShellModel()
        shell.loadSubtitles(from: try Self.file(Self.srt))

        shell.clearLyrics()

        #expect(shell.lyricSource == nil)
    }

    @Test("a file timed word by word is grouped into lines")
    func groupsWordTimedFile() throws {
        // Every word its own cue: placed as they are, a song is hundreds of
        // one-word clips. Grouped, they are the lines that were sung.
        let srt = """
        1
        00:00:10,640 --> 00:00:11,540
        Time

        2
        00:00:11,540 --> 00:00:11,900
        went

        3
        00:00:11,900 --> 00:00:12,260
        by

        4
        00:00:14,000 --> 00:00:14,300
        so

        5
        00:00:14,300 --> 00:00:15,000
        quickly

        """
        let shell = EditorShellModel()

        shell.loadSubtitles(from: try Self.file(srt))

        #expect(shell.lyricLines.map(\.text) == ["Time went by", "so quickly"])
        #expect(shell.lyricLines.map(\.start) == [10_640, 14_000])
        #expect(shell.lyricSource == .subtitles(name: "song.srt", byWord: true))
    }

    @Test("the grouping knobs regroup a word-timed file")
    func regroupsWordTimedFile() throws {
        let srt = "1\n00:00:01,000 --> 00:00:01,300\na\n\n2\n00:00:01,800 --> 00:00:02,100\nb\n\n3\n00:00:02,100 --> 00:00:02,400\nc\n"
        let shell = EditorShellModel()
        shell.loadSubtitles(from: try Self.file(srt))
        #expect(shell.lyricLines.count == 2)

        shell.regroupLyrics(gapThreshold: 1_000)

        #expect(shell.lyricLines.map(\.text) == ["a b c"])
    }

    @Test("the real word-timed file groups into lines, not hundreds of clips")
    func realFile() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/word-timed.srt")
        let shell = EditorShellModel()

        shell.loadSubtitles(from: url)

        #expect(shell.lyricSource == .subtitles(name: "word-timed.srt", byWord: true))
        #expect(shell.lyricLines.count < 60)
        #expect(shell.lyricLines.first?.text.hasPrefix("Time went by so quickly") == true)
        // Nothing lost in the grouping.
        let words = shell.lyricLines.reduce(0) { $0 + $1.text.split(separator: " ").count }
        #expect(words == 290)
    }

    @Test("the file picker accepts a .srt on a Mac with no subtitle app")
    func pickerAcceptsSrt() throws {
        // macOS gives an undeclared extension a dynamic type that conforms only
        // to `public.data`. A type built "conforming to text" is a *different*
        // dynamic identifier, and the picker greyed every .srt out (reported).
        let url = try Self.file(Self.srt)
        let type = try #require(try url.resourceValues(forKeys: [.contentTypeKey]).contentType)

        #expect(LyricsPanel.subtitleTypes.contains { type.conforms(to: $0) })
    }

    // ─── Karaoke ─────────────────────────────────────────────────────────────

    private static let wordTimed = """
    1
    00:00:10,000 --> 00:00:10,400
    Time

    2
    00:00:10,400 --> 00:00:10,800
    went

    3
    00:00:10,800 --> 00:00:11,200
    by

    """

    @Test("a placed line keeps when each of its words was sung")
    func placedLineCarriesSungWords() throws {
        let shell = EditorShellModel()
        shell.loadSubtitles(from: try Self.file(Self.wordTimed))

        shell.importLyrics(shell.lyricLines)

        let node = try #require(shell.effects.nodes.first)
        #expect(node.sungWords == [
            SungWord(start: 0, end: 400, characters: 4),
            SungWord(start: 400, end: 800, characters: 4),
            SungWord(start: 800, end: 1200, characters: 2),
        ])
    }

    @Test("Reveal makes words appear as they are sung")
    func revealSetsSungStagger() throws {
        let shell = EditorShellModel()
        shell.loadSubtitles(from: try Self.file(Self.wordTimed))
        shell.lyricWordTiming = .reveal

        // After a preset: karaoke is the point, and a preset's own stagger
        // would otherwise win.
        shell.importLyrics(shell.lyricLines, preset: TextEffect.presets.first)

        let node = try #require(shell.effects.nodes.first)
        #expect(node.values[TextEffect.Param.staggerMode] == .choice(SungTiming.choice))
        #expect(node.values[TextEffect.Param.unit] == .choice("Word"))
    }

    @Test("Highlight lights each word as it is sung")
    func highlightSetsSungSweep() throws {
        let shell = EditorShellModel()
        shell.loadSubtitles(from: try Self.file(Self.wordTimed))
        shell.lyricWordTiming = .highlight

        shell.importLyrics(shell.lyricLines)

        let node = try #require(shell.effects.nodes.first)
        #expect(node.values[TextEffect.Param.colourMode] == .choice("Highlight"))
        #expect(node.values[TextEffect.Param.sweepOrder] == .choice(SungTiming.choice))
    }

    @Test("Off leaves the preset's own sequence alone")
    func offTouchesNothing() throws {
        let shell = EditorShellModel()
        shell.loadSubtitles(from: try Self.file(Self.wordTimed))

        shell.importLyrics(shell.lyricLines)

        let node = try #require(shell.effects.nodes.first)
        #expect(node.values[TextEffect.Param.staggerMode] != .choice(SungTiming.choice))
        #expect(node.values[TextEffect.Param.sweepOrder] != .choice(SungTiming.choice))
    }

    @Test("a file timed by line has no words to sing")
    func lineTimedHasNoWords() throws {
        let shell = EditorShellModel()
        shell.loadSubtitles(from: try Self.file(Self.srt))
        shell.lyricWordTiming = .reveal

        shell.importLyrics(shell.lyricLines)

        #expect(!shell.lyricLinesHaveWordTiming)
        #expect(shell.effects.nodes.allSatisfy { $0.sungWords == nil })
        // Nothing to reveal by, so the setting does not reach the clip.
        #expect(shell.effects.nodes.allSatisfy {
            $0.values[TextEffect.Param.staggerMode] != .choice(SungTiming.choice)
        })
    }
}

