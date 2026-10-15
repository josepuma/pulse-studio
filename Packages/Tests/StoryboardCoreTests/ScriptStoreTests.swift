import Foundation
import Testing

@testable import StoryboardCore

/// Reading and writing a script's file inside the project folder.
///
/// Beside `ProjectFile` because it is the same job — the folder, and the files
/// in it that make up a project — and because `ScriptFile` guarantees the name
/// is a single component, so every path here is the folder plus one name and
/// there is no traversal left to check.
@Suite("Script store")
struct ScriptStoreTests {
    /// A migrated project has its code on disk and its node naming the file.
    @Test("inline source is written out and referenced")
    func migrationWritesTheFile() throws {
        let folder = try temporaryFolder()
        var document = EffectDocument()
        let track = document.addTrack(layer: .foreground)
        var node = document.add(ScriptEffect.descriptor, at: 0, duration: 4000, on: track.id)
        node.scriptSource = "sprite(Image.soft)"
        node.scriptFile = nil
        document[node.id] = node

        let migrated = try ScriptStore.migrate(document, inFolder: folder)

        let file = try #require(migrated[node.id]?.scriptFile)
        let written = try String(contentsOf: folder.appending(path: file.fileName), encoding: .utf8)
        #expect(written == "sprite(Image.soft)", "the code has to survive the move")
        #expect(migrated[node.id]?.needsScriptMigration == false)
    }

    /// Two clips with identical code get two files.
    ///
    /// De-duplicating by content would link clips the author never linked, and
    /// their next edit would change both.
    @Test("identical sources get separate files")
    func identicalSourcesGetSeparateFiles() throws {
        let folder = try temporaryFolder()
        var document = EffectDocument()
        let track = document.addTrack(layer: .foreground)
        let first = try migratable(&document, on: track.id, source: "sprite(Image.glow)")
        let second = try migratable(&document, on: track.id, source: "sprite(Image.glow)")

        let migrated = try ScriptStore.migrate(document, inFolder: folder)

        let a = try #require(migrated[first]?.scriptFile)
        let b = try #require(migrated[second]?.scriptFile)
        #expect(a != b, "each clip owns its own file")
    }

    /// A node already naming a file is not rewritten.
    @Test("a migrated node is left alone")
    func migratedNodeIsUntouched() throws {
        let folder = try temporaryFolder()
        var document = EffectDocument()
        let track = document.addTrack(layer: .foreground)
        var node = document.add(ScriptEffect.descriptor, at: 0, duration: 4000, on: track.id)
        node.scriptFile = ScriptFile(name: "already")
        node.scriptSource = "sprite(Image.soft)"
        document[node.id] = node

        let migrated = try ScriptStore.migrate(document, inFolder: folder)

        #expect(migrated[node.id]?.scriptFile == ScriptFile(name: "already"))
        #expect(
            !FileManager.default.fileExists(atPath: folder.appending(path: "already.js").path),
            "migration must not invent a file for a node that already names one",
        )
    }

    /// Reading a file that is not there is a reported absence, not a crash.
    @Test("a missing file reads as nil")
    func missingFileReadsAsNil() throws {
        let folder = try temporaryFolder()
        #expect(try ScriptStore.read(ScriptFile(name: "gone")!, inFolder: folder) == nil)
    }

    /// A written file reads back byte for byte.
    @Test("what is written is what is read")
    func roundTrip() throws {
        let folder = try temporaryFolder()
        let file = try #require(ScriptFile(name: "wave"))
        let code = "// a comment with 'quotes' and \\ backslashes\nsprite(Image.soft)\n"

        try ScriptStore.write(code, to: file, inFolder: folder)

        #expect(try ScriptStore.read(file, inFolder: folder) == code)
    }

    /// A name a script file cannot have does not become a file.
    @Test("creating a file never lands outside the folder")
    func namesStayInsideTheFolder() throws {
        let folder = try temporaryFolder()
        let file = try #require(ScriptStore.availableName(like: "../../escape", inFolder: folder))

        try ScriptStore.write("x", to: file, inFolder: folder)

        let written = folder.appending(path: file.fileName)
        #expect(
            written.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL,
            "a file must be a direct child of the project folder",
        )
    }

    /// A second script does not overwrite the first.
    @Test("an unavailable name is stepped past")
    func unavailableNamesAreStepped() throws {
        let folder = try temporaryFolder()
        let first = try #require(ScriptStore.availableName(like: "script", inFolder: folder))
        try ScriptStore.write("first", to: first, inFolder: folder)

        let second = try #require(ScriptStore.availableName(like: "script", inFolder: folder))

        #expect(second != first)
        #expect(try ScriptStore.read(first, inFolder: folder) == "first", "the first is intact")
    }

    // MARK: -

    private func migratable(
        _ document: inout EffectDocument,
        on trackID: EffectTrack.ID,
        source: String,
    ) throws -> EffectNode.ID {
        var node = document.add(ScriptEffect.descriptor, at: 0, duration: 4000, on: trackID)
        node.scriptSource = source
        node.scriptFile = nil
        document[node.id] = node
        return node.id
    }

    /// The folder's scripts are its `.js` files, whether or not a clip names
    /// them: deleting the last clip that ran a script does not delete the
    /// script.
    @Test("lists the folder's scripts and nothing else")
    func listsScripts() throws {
        let folder = try temporaryFolder()
        for name in ["wave.js", "Intro.js", "animate.d.ts", "jsconfig.json", "bg.png",
                     ".wave.js.saving", "storyboard.aesb"] {
            try Data().write(to: folder.appending(path: name))
        }
        // A directory named like a script is not one.
        try FileManager.default.createDirectory(
            at: folder.appending(path: "old.js"), withIntermediateDirectories: false)

        let files = try ScriptStore.files(inFolder: folder)

        #expect(files.map(\.name) == ["Intro", "wave"])
    }

    @Test("a folder that cannot be read lists nothing rather than throwing")
    func listsMissingFolder() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "script-store-absent-\(UUID().uuidString)")

        #expect(try ScriptStore.files(inFolder: folder).isEmpty)
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "script-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
