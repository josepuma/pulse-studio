import Foundation

/// The script files inside a project folder.
///
/// Beside `ProjectFile` because it is the same job — a folder, and the files in
/// it that make up one project — and it is the only other place in Core that
/// touches disk. The reason it can live here at all is `ScriptFile`: a
/// validated name is a single path component, so every path below is the folder
/// plus one name and there is no traversal left to check at the call site.
public enum ScriptStore {
    /// What the generated type declarations are called.
    ///
    /// Here rather than beside the generator because this is the layer that
    /// knows what files a project folder holds — the watcher has to recognise
    /// them without depending on the scripting runtime, which imports
    /// JavaScriptCore for reasons a file name has nothing to do with.
    public static let declarationsFileName = "animate.d.ts"

    /// What the editor configuration is called.
    ///
    /// `jsconfig.json` rather than `tsconfig.json`: the scripts are
    /// JavaScript, and this is the name an editor looks for beside plain `.js`.
    public static let configurationFileName = "jsconfig.json"

    /// Files a project folder holds that are generated rather than authored.
    ///
    /// A watcher must not react to these: they are written on project open, so
    /// treating one as an edit is a reload firing on our own write.
    public static let generatedFileNames = [declarationsFileName, configurationFileName]

    /// Reads a script's code, or `nil` when the file is not there.
    ///
    /// A missing file is an absence to report rather than an error to throw. It
    /// is what an author gets after deleting a `.js` outside the app, and the
    /// clip has to survive and say so — a project that refuses to open because
    /// one script went missing loses the other twenty.
    public static func read(_ file: ScriptFile, inFolder folder: URL) throws -> String? {
        let source = url(of: file, inFolder: folder)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        return try String(contentsOf: source, encoding: .utf8)
    }

    /// Writes a script's code.
    ///
    /// Written to a neighbouring file and moved into place, like the project
    /// itself: an interrupted write leaves the previous code intact rather than
    /// a truncated file, and truncated code is lost work.
    public static func write(_ code: String, to file: ScriptFile, inFolder folder: URL) throws {
        let destination = url(of: file, inFolder: folder)
        let temporary = folder.appending(path: ".\(file.fileName).saving")

        try Data(code.utf8).write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
    }

    /// Every script in the folder, by name.
    ///
    /// The folder's `.js` files, whether or not a clip names them: a script is
    /// a file, and removing the last clip that ran one does not delete it. A
    /// name `ScriptFile` refuses (a hidden temp write, say) is not a script.
    /// A folder that is not there lists nothing — it is the same absence a
    /// missing file is, not an error.
    public static func files(inFolder folder: URL) throws -> [ScriptFile] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }

        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
        )
        return contents
            .filter { $0.lastPathComponent.hasSuffix(ScriptFile.fileExtension) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .compactMap { ScriptFile(name: $0.lastPathComponent) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Where a script file sits. Always a direct child of the project folder.
    public static func url(of file: ScriptFile, inFolder folder: URL) -> URL {
        folder.appending(path: file.fileName)
    }

    /// A validated name close to `preferred` that nothing in the folder uses.
    ///
    /// Numbered rather than made unique with a UUID: a file the author is about
    /// to open in an editor is a file they have to recognise in a tab, and
    /// `wave-2.js` reads where `wave-3F2A88B1.js` does not.
    public static func availableName(like preferred: String, inFolder folder: URL) -> ScriptFile? {
        // Anything the reference type refuses is reduced to what it accepts
        // rather than rejected outright: this is called with a clip's name,
        // which a person typed and which may contain anything at all.
        let stem = sanitised(preferred)
        guard let first = ScriptFile(name: stem) else { return nil }

        guard FileManager.default.fileExists(atPath: url(of: first, inFolder: folder).path) else {
            return first
        }
        // Bounded, because an unbounded search on an unwritable folder would
        // spin forever rather than report that it cannot place the file.
        for suffix in 2 ... 999 {
            guard let candidate = ScriptFile(name: "\(stem)-\(suffix)") else { continue }
            let path = url(of: candidate, inFolder: folder).path
            if !FileManager.default.fileExists(atPath: path) { return candidate }
        }
        return nil
    }

    /// Moves every still-inline script in `document` out to a file.
    ///
    /// Projects written before scripts had files hold the code in the `.aesb`,
    /// which was the only place it existed — so a build that simply dropped the
    /// old key would open someone's work with empty script clips and nothing to
    /// say why. That is the loss the `"scale"`-to-two-axes migration exists to
    /// prevent, one format version earlier.
    ///
    /// Identical sources get **separate files**. Two clips carrying the same
    /// text were independently editable before, so sharing one file now would
    /// create a link the author never made and their next edit would silently
    /// change both. Sharing is what duplicating a clip means from here on; it
    /// is not something a migration may impose on work already finished.
    public static func migrate(_ document: EffectDocument, inFolder folder: URL) throws -> EffectDocument {
        var migrated = document

        for track in document.tracks {
            for node in track.nodes where node.needsScriptMigration {
                guard let source = node.scriptSource,
                      let file = availableName(like: node.name, inFolder: folder)
                else { continue }

                try write(source, to: file, inFolder: folder)

                var updated = node
                updated.scriptFile = file
                migrated[node.id] = updated
            }
        }

        return migrated
    }

    /// `preferred` reduced to something `ScriptFile` will accept.
    ///
    /// A clip's name is display text — it can hold slashes, dots, emoji and
    /// spaces — and it is the best starting point for a file name because it is
    /// what the author already calls that clip.
    private static func sanitised(_ preferred: String) -> String {
        let allowed = preferred.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character
                : "-"
        }
        // Collapsed and trimmed, so "My Clip // v2" becomes "My-Clip-v2"
        // rather than "My-Clip----v2".
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")

        // The fallback matters: a name made entirely of punctuation reduces to
        // nothing, and a script with no file is a script with no code.
        return collapsed.isEmpty ? "script" : String(collapsed.prefix(60))
    }
}
