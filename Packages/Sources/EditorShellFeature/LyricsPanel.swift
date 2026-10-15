import DesignSystem
import StoryboardCore
import SwiftUI
import UniformTypeIdentifiers

/// Turning a song into timed text clips.
///
/// The half of a lyric storyboard nobody can do by hand: the words are a search
/// away, and marking four hundred glyphs to twenty milliseconds is not.
///
/// What comes back is a **draft**. Measured over three real songs, Japanese
/// arrives at 0.97 median confidence with six per cent of lines worth checking,
/// and English at 0.61 with forty. So the panel's job is not to announce
/// success — it says which lines to look at, and lets them be placed one at a
/// time so each can carry a movement of its own.
struct LyricsPanel: View {
    @Bindable var shell: EditorShellModel

    /// Which language and region to listen for.
    ///
    /// Per session rather than saved with the project: a mapper works on one
    /// language at a time, and a project does not have a language — its song
    /// does.
    @State private var languages: [LyricTranscription.LanguageOption] = []
    @State private var language: String = ""
    @State private var variant: String = ""
    @State private var preset: String = LyricsPanel.noPreset
    @State private var isPickingSubtitles = false

    /// `.srt` by extension alone, and plain text for a `.txt` export.
    ///
    /// No `conformingTo:`. On a Mac where no app declares `.srt`, the system
    /// gives the file a dynamic type conforming only to `public.data`; a type
    /// built "conforming to text" is a *different* dynamic identifier, and the
    /// picker greyed every `.srt` out (reported). Built from the extension
    /// alone it is the same identifier the file carries — and where an app
    /// does declare `.srt`, it resolves to that declared type instead.
    static let subtitleTypes: [UTType] =
        [UTType(filenameExtension: "srt"), .plainText].compactMap { $0 }

    /// Standing in for "leave them still", which is a real choice rather than
    /// the absence of one.
    static let noPreset = "None"

    /// Below this a line was wrong more often than right, when measured.
    static let lowConfidence = 0.5

    var body: some View {
        // `loose` between groups, which is what the token is for: Song,
        // Grouping and the lines are three things, and at `regular` they read
        // as one list of fields.
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            // A subtitle file needs no speech engine, so the panel is never
            // hidden behind one: without it, only the Transcribe half goes.
            if shell.lyricTranscriptionHandler != nil {
                source
            }
            subtitles
            if let error = shell.lyricError {
                failure(error)
            }
            if shell.lyricLines.isEmpty {
                empty
            } else {
                if showsGrouping {
                    Divider().opacity(0.4)
                    grouping
                }
                Divider().opacity(0.4)
                results
            }
        }
        .task { await loadLanguages() }
        .fileImporter(isPresented: $isPickingSubtitles, allowedContentTypes: Self.subtitleTypes) { result in
            if case .success(let url) = result { shell.loadSubtitles(from: url) }
        }
    }

    // ─── Reading the song ────────────────────────────────────────────────────

    private var source: some View {
        // `compact` between controls in a group — `hair` is 2 points, meant for
        // an icon and its own label, and using it here is what had every field
        // touching its neighbour.
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            SectionHeader("Song")

            PropertyRow("Language") {
                MenuField(
                    items: languageItems,
                    selection: Binding(
                        get: { ChoiceOption(languageLabel) },
                        set: { selectLanguage($0.id) },
                    ),
                    label: \.id,
                )
            }

            // Shown only where there is something to choose. Japanese and
            // Korean have one region each; English has nine, and Chinese is
            // where it matters most — traditional and simplified are different
            // text on screen, not a dialect.
            if selectedLanguage?.hasChoice == true {
                PropertyRow("Region") {
                    MenuField(
                        items: variantItems,
                        selection: Binding(
                            get: { ChoiceOption(variantLabel) },
                            set: { selectVariant($0.id) },
                        ),
                        label: \.id,
                    )
                }
            }

            // Full width: it is the one action this section exists for, and
            // sized to its own label it reads as one control among the fields
            // rather than as the thing to press.
            HStack(spacing: Theme.Spacing.snug) {
                Button(
                    shell.isTranscribingLyrics ? "Listening…" : "Transcribe",
                    systemImage: "waveform",
                ) {
                    Task { await shell.transcribeLyrics(locale: variant) }
                }
                .buttonStyle(.themed(.primary, size: .small, fullWidth: true))
                .disabled(!shell.canTranscribeLyrics || shell.lyricAudioURL == nil || variant.isEmpty)

                if shell.isTranscribingLyrics {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    // ─── Reading a subtitle file ─────────────────────────────────────────────

    /// The other way in: somebody's timing, done by hand. Lines in the file
    /// are placed as they are; a file timed word by word is grouped like a
    /// transcription.
    private var subtitles: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            SectionHeader("Subtitles")

            Button("Load .srt", systemImage: "doc.text") { isPickingSubtitles = true }
                .buttonStyle(.themed(.secondary, size: .small, fullWidth: true))

            if case .subtitles(let name, let byWord) = shell.lyricSource {
                Text(byWord ? "\(name) · timed by word, grouped into lines" : name)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
    }

    /// The knobs fix where a machine — or a word-by-word file — breaks lines.
    /// A file timed by line already says where, and the knobs would do nothing.
    private var showsGrouping: Bool {
        shell.lyricSource != .subtitles(name: currentSubtitleName, byWord: false)
    }

    private var currentSubtitleName: String {
        if case .subtitles(let name, _) = shell.lyricSource { return name }
        return ""
    }

    // ─── The two knobs ───────────────────────────────────────────────────────

    /// Regrouping is free — the words stay in memory — so the numbers that
    /// decide where lines break belong beside them rather than behind a
    /// re-transcription.
    private var grouping: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            SectionHeader("Grouping")

            PropertyRow("Split Gap") {
                NumberField(
                    value: Binding(
                        get: { shell.lyricGapThreshold },
                        set: { shell.lyricGapThreshold = $0; shell.regroupLyrics() },
                    ),
                    unit: "ms", step: 20, range: 60...1200,
                )
            }

            PropertyRow("Max Length") {
                NumberField(
                    value: Binding(
                        get: { shell.lyricMaximumDuration / 1000 },
                        set: { shell.lyricMaximumDuration = $0 * 1000; shell.regroupLyrics() },
                    ),
                    unit: "s", step: 0.5, range: 2...20, format: "%.1f",
                )
            }
        }
    }

    // ─── The lines ───────────────────────────────────────────────────────────

    private var results: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            SectionHeader("\(shell.lyricLines.count) lines") {
                if let toCheck {
                    Text(toCheck)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.warning)
                }
            }

            // Both chosen before placing and changeable between one line and
            // the next: that is the point of placing them one at a time.
            PropertyRow("Movement") {
                MenuField(
                    items: presetNames.map(ChoiceOption.init),
                    selection: Binding(get: { ChoiceOption(preset) }, set: { preset = $0.id }),
                    label: \.id,
                )
            }

            // Only where the lines know their words: a file timed by line has
            // nothing to sing by, and a menu that does nothing lies.
            if shell.lyricLinesHaveWordTiming {
                PropertyRow("Karaoke") {
                    MenuField(
                        items: EditorShellModel.LyricWordTiming.allCases.map { ChoiceOption($0.rawValue) },
                        selection: Binding(
                            get: { ChoiceOption(shell.lyricWordTiming.rawValue) },
                            set: { shell.lyricWordTiming = .init(rawValue: $0.id) ?? .off },
                        ),
                        label: \.id,
                    )
                }
            }

            // The clip's scale, not the font size: a font size change mints a
            // texture per glyph, and a slider dragged across its range would
            // coin a set per step.
            PropertyRow("Size") {
                NumberField(
                    value: $shell.lyricScale,
                    step: 0.05, range: 0.1...4, format: "%.2f",
                )
            }

            ScrollView {
                // `tight` between rows: at one point they merge into a block
                // of text, and the timestamp column stops reading as a column.
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    ForEach(shell.lyricLines) { line in
                        LyricLineRow(
                            text: line.text,
                            start: line.start,
                            duration: line.duration,
                            isOverlong: line.isOverlong,
                            needsReview: (line.confidence ?? 1) < Self.lowConfidence,
                            isPlaced: shell.placedLyricLines.contains(line.id),
                            seek: { shell.seekHandler?(line.start) },
                            place: { shell.importLyricLine(line, preset: selectedPreset) },
                        )
                    }
                }
            }
            .frame(maxHeight: 300)

            HStack(spacing: Theme.Spacing.snug) {
                Button("Place All", systemImage: "plus.square.on.square") {
                    shell.importLyrics(shell.lyricLines, preset: selectedPreset)
                }
                .buttonStyle(.themed(.primary, size: .small, fullWidth: true))

                // Ghost, not secondary: it sits beside the primary action and
                // is the one nobody is reaching for.
                Button("Discard", systemImage: "trash") { shell.clearLyrics() }
                    .buttonStyle(.themed(.ghost, size: .small))
            }
        }
    }

    /// What needs a look, said once rather than left to be discovered: it is
    /// the difference between checking every line and checking six.
    private var toCheck: String? {
        var low = 0
        var long = 0
        for line in shell.lyricLines {
            if (line.confidence ?? 1) < Self.lowConfidence { low += 1 }
            if line.isOverlong { long += 1 }
        }
        var parts: [String] = []
        if low > 0 { parts.append("\(low) unsure") }
        if long > 0 { parts.append("\(long) long") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var empty: some View {
        Text(shell.lyricTranscriptionHandler == nil
            ? "Load a .srt to place its lines. Transcribing the song needs macOS 26 or newer."
            : "Transcribe the song, or load a .srt, to see the lines it was sung as.")
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.secondary)
    }

    private func failure(_ message: String) -> some View {
        Text(message)
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.warning)
    }

    // ─── Presets ─────────────────────────────────────────────────────────────

    private var presetNames: [String] {
        [Self.noPreset] + TextEffect.presets.map(\.name)
    }

    private var selectedPreset: EffectPreset? {
        TextEffect.presets.first { $0.name == preset }
    }

    // ─── Languages ───────────────────────────────────────────────────────────

    private var selectedLanguage: LyricTranscription.LanguageOption? {
        languages.first { $0.name == language }
    }

    private var languageItems: [ChoiceOption] {
        languages.isEmpty ? [ChoiceOption(languageLabel)] : languages.map { ChoiceOption($0.name) }
    }

    private var languageLabel: String {
        language.isEmpty ? "—" : language
    }

    private var variantItems: [ChoiceOption] {
        (selectedLanguage?.variants ?? []).map { ChoiceOption($0.label) }
    }

    private var variantLabel: String {
        selectedLanguage?.variants.first { $0.identifier == variant }?.label ?? "—"
    }

    private func selectLanguage(_ name: String) {
        language = name
        // Its preferred region comes with it: an installed model starts in
        // seconds and anything else downloads first.
        variant = languages.first { $0.name == name }?.preferred ?? ""
    }

    private func selectVariant(_ label: String) {
        guard let match = selectedLanguage?.variants.first(where: { $0.label == label }) else {
            return
        }
        variant = match.identifier
    }

    private func loadLanguages() async {
        guard languages.isEmpty else { return }
        guard let build = shell.lyricLanguagesHandler else { return }
        languages = await build()
        guard let first = languages.first else { return }
        // Start on a language whose model is here, if any: it is the one that
        // transcribes without a download.
        let ready = languages.first { $0.variants.contains(where: \.isInstalled) }
        selectLanguage((ready ?? first).name)
    }
}
