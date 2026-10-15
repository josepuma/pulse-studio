import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// The library's script cards: one per file, and renaming one.
///
/// Built on a real project folder, because both halves are about the disk —
/// which files exist, what their first lines say, and what a rename moves.
@Suite("Script library", .serialized)
@MainActor
struct ScriptLibraryTests {
    // ─── Listing ─────────────────────────────────────────────────────────────

    @Test("one entry per file, ordered by its first clip on the timeline")
    func onePerFile() throws {
        let (shell, _, ids) = try project()

        let entries = shell.scriptEntries
        #expect(entries.map(\.file.name) == ["intro", "wave"])
        #expect(entries[0].clipIDs == [ids.intro])
        // The file two clips share lists them earliest first: that is the clip
        // a click on the card selects, whatever order they were placed in.
        #expect(entries[1].clipIDs == [ids.waveEarly, ids.waveLate])
    }

    @Test("an entry carries the first lines of its file")
    func snippet() throws {
        let (shell, _, _) = try project()

        let wave = try #require(shell.scriptEntries.first { $0.file.name == "wave" })
        #expect(wave.snippet == ["const rows = 12", "sprite(Image.glow)"])
        #expect(!wave.isMissing)
    }

    @Test("a file that is not on disk is missing, with no snippet")
    func missing() throws {
        let (shell, _, _) = try project(skipping: "intro")

        let intro = try #require(shell.scriptEntries.first { $0.file.name == "intro" })
        #expect(intro.isMissing)
        #expect(intro.snippet.isEmpty)
    }

    // ─── Files without clips ─────────────────────────────────────────────────

    /// Reported: removing duplicate clips from the timeline took the script
    /// out of the Scripts tab with them. The file was still on disk — the panel
    /// only listed files some clip named.
    @Test("removing a file's last clip keeps its card")
    func lastClipRemoved() throws {
        let (shell, _, ids) = try project()

        shell.removeEffect(ids.intro)

        let intro = try #require(shell.scriptEntries.first { $0.file.name == "intro" })
        #expect(intro.clipIDs.isEmpty)
        #expect(intro.trackID == nil)
        #expect(!intro.isMissing)
        #expect(intro.snippet == ["text('hello')"])
    }

    @Test("a script on disk that no clip names is listed")
    func unplacedFileListed() throws {
        let (shell, folder, _) = try project()
        try ScriptStore.write("sprite(Image.star)", to: try file("loose"), inFolder: folder)

        shell.reloadScripts()

        let loose = try #require(shell.scriptEntries.first { $0.file.name == "loose" })
        #expect(loose.clipIDs.isEmpty)
        #expect(loose.snippet == ["sprite(Image.star)"])
    }

    @Test("files with no clip come after the placed ones, by name")
    func unplacedOrder() throws {
        let (shell, folder, ids) = try project()
        try ScriptStore.write("", to: try file("zeta"), inFolder: folder)
        try ScriptStore.write("", to: try file("alpha"), inFolder: folder)
        shell.reloadScripts()

        shell.removeEffect(ids.intro)

        #expect(shell.scriptEntries.map(\.file.name) == ["wave", "alpha", "intro", "zeta"])
    }

    @Test("a card with no clip still opens its file")
    func unplacedOpens() throws {
        let (shell, folder, ids) = try project()
        shell.removeEffect(ids.intro)
        var opened: URL?
        shell.openScriptHandler = { url in opened = url; return true }

        shell.openScriptExternally(file: try file("intro"))

        #expect(opened == ScriptStore.url(of: try file("intro"), inFolder: folder))
    }

    @Test("an edit on disk reaches the snippet after a reload")
    func reloadRefreshesSnippet() throws {
        let (shell, folder, _) = try project()
        let wave = try file("wave")
        try ScriptStore.write("sprite(Image.soft)", to: wave, inFolder: folder)

        shell.reloadScripts()

        let entry = try #require(shell.scriptEntries.first { $0.file == wave })
        #expect(entry.snippet == ["sprite(Image.soft)"])
    }

    // ─── Status ──────────────────────────────────────────────────────────────

    @Test("a failed run marks its file; a truncated one does not")
    func failure() throws {
        let (shell, _, ids) = try project()
        shell.scriptReport = { id in
            switch id {
            case ids.waveLate:
                ScriptRuntime.Report(diagnostics: [.runtimeFailed("boom")], logs: [])
            case ids.intro:
                // Kept 2000 of 2400: it still drew, and a red card for that
                // would cry wolf on a script that works.
                ScriptRuntime.Report(diagnostics: [.spritesTruncated(produced: 2400, kept: 2000)], logs: [])
            default: nil
            }
        }

        let entries = shell.scriptEntries
        let intro = try #require(entries.first { $0.file.name == "intro" })
        let wave = try #require(entries.first { $0.file.name == "wave" })
        // Any clip of the file failing is the file failing.
        #expect(shell.scriptFailure(of: wave) == "boom")
        #expect(shell.scriptFailure(of: intro) == nil)
    }

    // ─── Placing ─────────────────────────────────────────────────────────────

    @Test("a card's click places a clip sharing its file, writing no new one")
    func addClipSharesTheFile() throws {
        let (shell, folder, _) = try project()
        let intro = try file("intro")
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()

        let placed = try #require(shell.addScriptClip(using: intro, at: 8000))

        #expect(placed.scriptFile == intro)
        // `addEffect` writes a fresh file per script clip; this must not, or
        // the "shared" clip would run a copy rather than the same code.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == before)
        #expect(shell.scriptEntries.first { $0.file == intro }?.clipIDs.count == 2)
    }

    @Test("placing a clip from a card is an ordinary, undoable edit")
    func addClipIsUndoable() throws {
        let (shell, _, _) = try project()
        let intro = try file("intro")
        let count = shell.effects.nodes.count

        shell.addScriptClip(using: intro, at: 8000)
        #expect(shell.effects.nodes.count == count + 1)

        shell.undo()
        #expect(shell.effects.nodes.count == count)
    }

    // ─── Renaming ────────────────────────────────────────────────────────────

    @Test("a rename moves the file and every clip follows it")
    func rename() throws {
        let (shell, folder, ids) = try project()
        let wave = try file("wave")
        let ocean = try file("ocean")
        let intro = try file("intro")

        #expect(shell.renameScript(wave, to: "ocean"))

        #expect(FileManager.default.fileExists(atPath: ScriptStore.url(of: ocean, inFolder: folder).path))
        #expect(!FileManager.default.fileExists(atPath: ScriptStore.url(of: wave, inFolder: folder).path))
        #expect(shell.effects[ids.waveEarly]?.scriptFile == ocean)
        #expect(shell.effects[ids.waveLate]?.scriptFile == ocean)
        #expect(shell.effects[ids.intro]?.scriptFile == intro)
        #expect(shell.scriptEntries.first { $0.file == ocean }?.snippet.first == "const rows = 12")
    }

    @Test("a rename is saved but not undoable")
    func renameIsNotUndoable() throws {
        let (shell, _, _) = try project()
        let couldUndo = shell.canUndo
        #expect(!shell.hasUnsavedChanges)

        let wave = try file("wave")
        shell.renameScript(wave, to: "ocean")

        // ⌘Z cannot rename the file back, and undoing only the references
        // would point the clips at a file that no longer exists.
        #expect(shell.canUndo == couldUndo)
        #expect(shell.hasUnsavedChanges)
    }

    @Test("a rename onto an existing file is refused and changes nothing")
    func renameOntoExisting() throws {
        let (shell, folder, ids) = try project()
        let wave = try file("wave")
        let intro = try file("intro")
        let before = try String(contentsOf: ScriptStore.url(of: intro, inFolder: folder), encoding: .utf8)

        #expect(!shell.renameScript(wave, to: "intro"))

        // Never over another file: its code would be gone with no undo.
        let after = try String(contentsOf: ScriptStore.url(of: intro, inFolder: folder), encoding: .utf8)
        #expect(after == before)
        #expect(FileManager.default.fileExists(atPath: ScriptStore.url(of: wave, inFolder: folder).path))
        #expect(shell.effects[ids.waveEarly]?.scriptFile == wave)
        #expect(shell.saveError != nil)
    }

    @Test("a name that is not a safe file name is refused", arguments: ["", "a/b", "..", ".hidden"])
    func renameInvalid(_ name: String) throws {
        let (shell, folder, ids) = try project()
        let wave = try file("wave")

        #expect(!shell.renameScript(wave, to: name))
        #expect(FileManager.default.fileExists(atPath: ScriptStore.url(of: wave, inFolder: folder).path))
        #expect(shell.effects[ids.waveEarly]?.scriptFile == wave)
    }

    // MARK: -

    private struct IDs {
        let intro: EffectNode.ID
        let waveEarly: EffectNode.ID
        let waveLate: EffectNode.ID
    }

    /// A project with two script files: `wave`, shared by two clips placed
    /// late-then-early, and `intro`, before both.
    private func project(skipping missing: String? = nil) throws -> (EditorShellModel, URL, IDs) {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "script-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let wave = try file("wave")
        let intro = try file("intro")
        if missing != "wave" {
            try ScriptStore.write("const rows = 12\nsprite(Image.glow)", to: wave, inFolder: folder)
        }
        if missing != "intro" {
            try ScriptStore.write("text('hello')", to: intro, inFolder: folder)
        }

        var built = EffectDocument()
        let track = built.addTrack(layer: .foreground)
        let late = script(in: &built, track: track.id, at: 3000, file: wave)
        let early = script(in: &built, track: track.id, at: 1000, file: wave)
        let first = script(in: &built, track: track.id, at: 500, file: intro)
        try ProjectFile.write(Project(document: built), toFolder: folder)

        let shell = EditorShellModel()
        shell.loadProject(fromFolder: folder)
        return (shell, folder, IDs(intro: first, waveEarly: early, waveLate: late))
    }

    private func script(
        in document: inout EffectDocument,
        track: EffectTrack.ID,
        at start: Double,
        file: ScriptFile,
    ) -> EffectNode.ID {
        var node = document.add(ScriptEffect.descriptor, at: start, duration: 1000, on: track)
        node.scriptFile = file
        node.scriptSource = nil
        document[node.id] = node
        return node.id
    }

    private func file(_ name: String) throws -> ScriptFile {
        try #require(ScriptFile(name: name))
    }
}
