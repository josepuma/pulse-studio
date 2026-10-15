import DesignSystem
import StoryboardCore
import SwiftUI

/// The left panel: whatever the rail has selected.
struct SidePanelView: View {
    /// Fixed width, so the shell can size the workspace around the canvas.
    ///
    /// 300 rather than the 240 it started at: the panels hold rows of a label
    /// and a control, and at 240 the control had about 130 points — enough for
    /// a number, not for a menu. "China continental (simplificado)" is
    /// thirty-two characters and was truncated on screen.
    ///
    /// This feeds ``EditorShellView/minimumWidth``, so it is not free: the
    /// window's floor moves with it, from 1076 to 1136 points. That is still
    /// well inside a 13-inch display's 1470, which is what makes the room
    /// affordable.
    static let width: CGFloat = 300


    @Bindable var shell: EditorShellModel
    /// Where a newly added effect is placed.
    /// Read when something is placed, not when the panel is built.
    ///
    /// Taken as a value, the panel holds whatever the clock said at build time
    /// — stale by the time anyone clicks — and the read ties the panel to
    /// whoever supplies it. The same closure the keyframe row already uses.
    var playheadNow: () -> Double = { 0 }

    /// Which effect's presets are open, if any.
    ///
    /// One at a time: with every group expanded the list is exactly the flat
    /// list this grouping exists to avoid.
    @State private var expandedEffect: String?

    /// What is typed into the search box.
    @State private var query = ""

    /// Which filter category the grid is narrowed to, or nothing for all.
    ///
    /// Not persisted: it is a way of looking through the list, not a setting.
    @State private var filterCategory: FilterCategory?

    /// What the preset list is narrowed to, or nothing for everything.
    @State private var selectedFilter: PresetFilter?

    /// How wide the panel is: wide for a script, narrow otherwise.
    ///
    /// It used to narrow again when the inspector was open, so that both fit.
    /// Dropped: code should not shrink because another panel was opened, and
    /// the canvas is what has room to give. One width per state is also one
    /// fewer thing to reason about while typing.
    private var panelWidth: CGFloat {
        Self.width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            SectionHeader(shell.sidePanel.title) {
                // One place and one mark for "add" in every panel that can
                // add something: the accent + at the end of the heading. Each
                // panel used to say it its own way — a grey + in the filter
                // row, an icon button by the track count, a card in the grid —
                // and a control that moves between panels is one that has to be
                // looked for each time.
                switch shell.sidePanel {
                case .assets: importAssetsMenu
                case .effects: newEffectMenu
                case .scripts: newScriptButton
                case .layers: newTrackButton
                // Filters are applied, not created; Lyrics' action is to
                // transcribe, which lives with its settings.
                case .filters, .lyrics: EmptyView()
                }
            }

            switch shell.sidePanel {
            case .assets: assets
            case .effects: library
            case .scripts: scripts
            case .filters: filtersPanel
            case .layers: layers
            case .lyrics: LyricsPanel(shell: shell)
            }
        }
        .padding(Theme.Spacing.compact)
        // Wide while a script is open, so code has somewhere to live.
        // `maxWidth`, not a fixed `width`.
        //
        // The wide editor asks for 620 while the window's own minimum budgets
        // 240, so in a small window with the inspector open the canvas was
        // left 100 points of the 480 it needs — measured. A maximum lets the
        // layout resolve that the way it resolves every other squeeze, and
        // costs the editor width only when there is none to take.
        .frame(maxWidth: panelWidth, alignment: .top)
        .layoutPriority(-1)
        .animation(Theme.Motion.standard, value: panelWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .surface(.panel)
    }

    // ─── Assets ──────────────────────────────────────────────────────────────

    private var assets: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            HStack(spacing: Theme.Spacing.tight) {
                ChipPicker(
                    items: AssetItem.Kind.allCases,
                    selection: $shell.assetFilter,
                    label: \.title,
                )

            }

            if shell.visibleAssets.isEmpty {
                ComingSoon(
                    title: "No assets",
                    detail: "Images and sounds in the beatmap folder appear here. Import to add more.",
                    systemImage: "photo.on.rectangle.angled",
                )
            } else {
                ScrollView {
                    // A grid of pictures, not a list of filenames.
                    //
                    // An asset panel exists to answer "which one is this", and
                    // a name answers it only for whoever wrote it: `sb/1.png`
                    // tells you nothing, and finding out means placing it and
                    // looking. The picture *is* the label.
                    //
                    // Two columns rather than more: the panel is narrow, and a
                    // thumbnail small enough to fit three is too small to
                    // recognise — which puts the reader back to reading names.
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: Theme.Spacing.tight),
                            GridItem(.flexible(), spacing: Theme.Spacing.tight),
                        ],
                        spacing: Theme.Spacing.tight,
                    ) {
                        ForEach(shell.visibleAssets) { asset in
                            AssetCard(
                                asset: asset,
                                thumbnail: shell.thumbnail(for: asset.path),
                            ) {
                                shell.placeAsset(at: asset.path, time: playheadNow())
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.tight)
                }
            }
        }
    }

    // ─── Scripts ─────────────────────────────────────────────────────────────

    /// The effect library, and what has been placed from it.
    ///
    /// Effects and scripts share this panel because they will be the same
    /// thing: a scripted effect declares the same descriptor a native one does,
    /// and will appear in this list beside them.
    /// The project's scripts, as cards — and only as cards.
    ///
    /// A card is acted on, not opened: a click places another clip running
    /// that file, and the card's edit button opens the file in the editor. It
    /// used to swap the list for the selected clip's script panel, which is a
    /// second screen to get lost in for what are two actions.
    private var scripts: some View {
        scriptList
    }

    /// Every script file the project uses.
    private var scriptList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            search

            ScrollView {
                LazyVGrid(columns: Self.cardColumns, alignment: .leading, spacing: Theme.Spacing.snug) {
                    ForEach(visibleScripts) { entry in
                        scriptCard(entry)
                    }
                }

                if visibleScripts.isEmpty {
                    if query.isEmpty {
                        ComingSoon(
                            title: "No scripts yet",
                            detail: "Start one with the + above — it opens in your code editor.",
                            systemImage: "curlybraces",
                        )
                    } else {
                        Text("Nothing matches")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.tertiary)
                            .padding(.top, Theme.Spacing.compact)
                    }
                }
            }
        }
    }

    /// The effect library: search, filters and the presets.
    private var library: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            search
            packFilter

            ScrollView {
                // Cards, not rows: the preview *is* the entry. It plays inside
                // the card under the pointer — the floating popover that used
                // to show it is gone, since a preview that opens beside the
                // thing it describes covers the next one down the list.
                //
                // Lazy, so a card is only built — and only asks for its
                // preview — once it scrolls into view.
                LazyVGrid(columns: Self.cardColumns, alignment: .leading, spacing: Theme.Spacing.snug) {
                    ForEach(visiblePresets, id: \.id) { preset in
                        EffectPreviewCard(
                            title: preset.name,
                            systemImage: shell.library.descriptor(for: preset.effectType)?.systemImage
                                ?? "sparkles",
                            tint: Theme.Palette.tertiary,
                            frames: shell.preview(of: .preset(preset)),
                            action: { shell.addPreset(preset, at: playheadNow()) },
                        )
                        // The summary is what makes a grid of names browsable:
                        // "Snow" and "Rain" are obvious, "Magic" and
                        // "Starfield" are not.
                        .help("\(preset.summary)\nClick to add at the playhead")
                        .onAppear { shell.requestPreview(for: .preset(preset)) }
                    }
                }

                if visiblePresets.isEmpty, !query.isEmpty {
                    Text("Nothing matches")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                        .padding(.top, Theme.Spacing.compact)
                }
            }
            // A new scroll view per filter, rather than scrolling the old one
            // back.
            //
            // A scroll view keeps its offset and the next list is usually
            // shorter, so switching tabs while scrolled down left the panel
            // parked past the end of the new one, showing nothing until it was
            // dragged back by hand.
            //
            // `scrollTo` cannot fix it: the anchor lives in a lazy container,
            // which does not build what is off screen — scrolled to the bottom
            // there is no top view to scroll to. Changing the identity throws
            // the offset away with the view, and a fresh one starts at the top
            // by definition.
            .id("presets-\(String(describing: selectedFilter))-\(query)")
        }
    }

    /// Every effect that can be placed blank, behind one button.
    ///
    /// This used to be a row of nine glyphs kept above the library — Emitter,
    /// Image, Script, Shape, Text, Tile Wipe, Audio Bars, Audio Waves, Signal
    /// Loss — with no labels, repeating the chips right under it and crowding
    /// the grid that is what the panel is for. A menu costs one click more and
    /// gives every entry its name, grouped the way the filters are.
    private var newEffectMenu: some View {
        Menu {
            ForEach(LibraryCategory.displayOrder, id: \.self) { category in
                let inCategory = shell.creatableDescriptors.filter { $0.category == category }
                if !inCategory.isEmpty {
                    Section(category.rawValue) {
                        ForEach(inCategory, id: \.type) { descriptor in
                            Button(descriptor.name, systemImage: descriptor.systemImage) {
                                shell.addEffect(descriptor, at: playheadNow())
                            }
                        }
                    }
                }
            }
        } label: {
            AddBadge(isHighlighted: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add a blank effect at the playhead")
    }

    /// Images into the project, from disk.
    ///
    /// A menu rather than a button, because the destination is a real fork:
    /// the root is the beatmap's own art and `sb/` is the storyboard's, and a
    /// file in the wrong one is broken in a way nothing shows until export.
    /// Choosing for the author is what put a background in `sb/` and made a
    /// mess to untangle.
    private var importAssetsMenu: some View {
        Menu {
            ForEach(AssetDestination.allCases) { destination in
                Button {
                    shell.importAssetsFromDisk(into: destination)
                } label: {
                    Text(destination.title)
                    Text(destination.detail)
                }
            }
        } label: {
            AddBadge(isHighlighted: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!shell.canImportAssets)
        // A plain style draws the label as given, disabled or not, so the
        // dimming is said here — a lit + that does nothing is a control that
        // lies.
        .opacity(shell.canImportAssets ? 1 : 0.4)
        .help("Import images")
    }

    /// A new, empty track.
    private var newTrackButton: some View {
        Button { shell.addTrack() } label: {
            AddBadge(isHighlighted: true)
        }
        .buttonStyle(.plain)
        .help("New track")
    }

    /// A new script clip, with a fresh file to edit — the Scripts tab's `+`,
    /// the same mark and the same place as the Effects tab's.
    ///
    /// A button, not a card in the grid: a "New Script" card sat among the
    /// file cards in a different shape from all of them, and the panel had two
    /// ways to say "add" where Effects has one.
    private var newScriptButton: some View {
        Button {
            guard let script = shell.library.descriptor(for: ScriptEffect.descriptor.type) else { return }
            shell.addEffect(script, at: playheadNow())
        } label: {
            AddBadge(isHighlighted: true)
        }
        .buttonStyle(.plain)
        .help("Add a script clip at the playhead, with a new file to edit")
    }

    /// The script cards on show, narrowed by the search like everything else.
    private var visibleScripts: [ScriptEntry] {
        shell.scriptEntries.filter { matches($0.file.name) }
    }

    /// One script file as a card.
    ///
    /// A click places another clip running the same file at the playhead —
    /// what a click on any card in the library does. The edit button opens the
    /// file in the editor; the menu also renames it. One card per file, so a
    /// file three clips share is one card marked ×3 — editing it reloads all
    /// three.
    private func scriptCard(_ entry: ScriptEntry) -> some View {
        let status: ScriptCard.Status = if entry.isMissing {
            .missing
        } else if let failure = shell.scriptFailure(of: entry) {
            .failed(failure)
        } else {
            .ready
        }

        return ScriptCard(
            fileName: entry.file.fileName,
            editableName: entry.file.name,
            snippet: entry.snippet,
            status: status,
            clipCount: entry.clipIDs.count,
            tint: entry.trackID
                .flatMap { id in shell.effects.tracks.first { $0.id == id }?.tint }
                ?? Theme.Palette.tertiary,
            isSelected: shell.selectedNodeID.map(entry.clipIDs.contains) ?? false,
            action: { shell.addScriptClip(using: entry.file, at: playheadNow()) },
            rename: { shell.renameScript(entry.file, to: $0) },
            openInEditor: entry.isMissing ? nil : {
                shell.openScriptExternally(file: entry.file)
            },
        )
    }

    /// Which pack the list is showing, as a row of chips.
    ///
    /// A filter rather than a container. Packs nested inside a "Packs" heading
    /// put a category above the categories — three levels deep for a library
    /// this size, and two chevrons that looked identical without meaning the
    /// same thing.
    @ViewBuilder
    private var packFilter: some View {
        // Effects first, then packs.
        //
        // Chips that only named packs reached seven presets out of thirty-seven:
        // everything from the text effect and every plain emitter preset
        // belonged to no pack, so each chip held one or two while "All" held
        // the rest. A filter that leaves most of the library unreachable is one
        // that was not finished.
        //
        // By effect rather than by inventing a "Basics" pack for the leftovers:
        // a text preset genuinely *is* a text preset, while "Basics" would mean
        // "the others" — a name for a gap rather than for a thing.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.tight) {
                chip(nil, label: "All")

                ForEach(shell.library.descriptors, id: \.type) { descriptor in
                    if shell.presets.contains(where: {
                        $0.effectType == descriptor.type && $0.pack == nil
                    }) {
                        chip(.effect(descriptor.type), label: descriptor.name)
                    }
                }

                ForEach(shell.packs.map(\.name), id: \.self) { pack in
                    chip(.pack(pack), label: pack)
                }
            }
        }
        // The row is chips, not a scrolling region: without this it takes
        // whatever height a scroll view asks for, which is all of it.
        .frame(height: Theme.Size.controlSmall)
    }

    private func chip(_ filter: PresetFilter?, label: String) -> some View {
        FilterChip(label, isSelected: selectedFilter == filter) {
            selectedFilter = filter
        }
    }

    /// Two columns: at the panel's width a card is still wide enough to read
    /// a preview, and three would shrink each to a thumbnail of a thumbnail.
    private static let cardColumns = [
        GridItem(.flexible(), spacing: Theme.Spacing.snug),
        GridItem(.flexible(), spacing: Theme.Spacing.snug),
    ]

    /// The presets on show: everything, or one pack, narrowed by the search.
    private var visiblePresets: [EffectPreset] {
        shell.presets.filter { preset in
            let kept = switch selectedFilter {
            case .none: true
            // An effect's chip shows its own presets, not the packs built from
            // it: a pack is a thing in its own right and has a chip of its own.
            case let .effect(type): preset.effectType == type && preset.pack == nil
            case let .pack(name): preset.pack == name
            }
            return kept && matches(preset.name)
        }
    }


    /// Whether a name and its presets match what is typed.
    ///
    /// Matched on the preset names too, not only the effect's: someone hunting
    /// for "portal" is looking for a preset, and a search that only reads the
    /// row above it would come back empty on the thing they can see in the
    /// panel.
    private func matches(_ name: String, presets: [EffectPreset] = []) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = query.lowercased()
        return name.lowercased().contains(needle)
            || presets.contains { $0.name.lowercased().contains(needle) }
    }

    /// Filters the library as you type.
    ///
    /// Search beats hierarchy once a list stops fitting on screen: the groups
    /// are for browsing, this is for when you already know the name. After
    /// Effects puts one at the top of its effects panel for the same reason —
    /// nobody opens six folders to find something they can spell.
    private var search: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)

            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.label)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.compact)
        .frame(height: Theme.Size.controlSmall)
        .surface(.inset, radius: Theme.Radius.control)
    }

    // ─── Filters ─────────────────────────────────────────────────────────────

    /// The filter library, in a tab of its own.
    ///
    /// Apart from the effects because they are different things: one makes
    /// something out of nothing, the other needs something to already be there.
    /// Sharing a panel implied a filter could be dropped on an empty timeline.
    private var filtersPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            Text("Drag onto a clip to apply")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)

            search

            filterCategoryChips

            let visible = FilterCategory.visible(
                in: shell.filterDescriptors,
                chip: filterCategory,
                query: query,
            )

            ScrollView {
                if visible.isEmpty {
                    Text("Nothing matches")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                        .padding(.top, Theme.Spacing.compact)
                } else {
                    LazyVGrid(
                        columns: Self.cardColumns,
                        alignment: .leading,
                        spacing: Theme.Spacing.snug,
                    ) {
                        ForEach(visible, id: \.type) { descriptor in
                            filterCard(descriptor)
                        }
                    }
                }
            }
            // Changing the chip or the query swaps the whole grid; a scroll
            // offset from the old one would land past the end of the new.
            .id("filters-\(String(describing: filterCategory))-\(query)")
        }
    }

    /// The filter categories as chips: what a filter does to a clip.
    ///
    /// These replaced collapsible headers. Folding sections away served a list
    /// long enough to need it; with eighteen filters, one tap to narrow to a
    /// category beats scrolling past six headers. Categories with nothing in
    /// them have no chip, and the row never reacts to the search box.
    private var filterCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.tight) {
                FilterChip("All", isSelected: query.isEmpty && filterCategory == nil) {
                    filterCategory = nil
                }

                ForEach(FilterCategory.visibleChips(in: shell.filterDescriptors), id: \.self) { category in
                    FilterChip(category.rawValue, isSelected: query.isEmpty && filterCategory == category) {
                        filterCategory = category
                    }
                }
            }
        }
        // A chip row, not a scrolling region: without this it asks for all the
        // height there is.
        .frame(height: Theme.Size.controlSmall)
    }

    /// One filter as a card, its preview drawn over the same fixed subject as
    /// every other — Glow beside Blur over identical input is the comparison
    /// someone choosing between them is making.
    ///
    /// Still a thing you **drag**: onto a clip on the timeline, the way a
    /// library works in any editor. A click applies it to the selected clip
    /// when there is one.
    private func filterCard(_ descriptor: FilterDescriptor) -> some View {
        let canApply = shell.selectedEffect != nil

        return EffectPreviewCard(
            title: descriptor.name,
            systemImage: descriptor.systemImage,
            // Filters share one colour everywhere — the library, a clip, the
            // keyframe editor — so a filter reads as a filter.
            tint: Theme.KeyframePalette.filter,
            frames: shell.preview(of: .filter(descriptor)),
            action: {
                guard let node = shell.selectedEffect else { return }
                shell.addFilter(descriptor, to: node.id)
            },
        )
        // The type carried is the filter's own, so a drop can tell a filter
        // from anything else that might be dragged over a lane.
        .draggable(FilterTransfer(type: descriptor.type).payload) {
            Label(descriptor.name, systemImage: descriptor.systemImage)
                .font(Theme.Typography.label)
                .padding(Theme.Spacing.snug)
                .background(.thinMaterial, in: Capsule())
        }
        .help(canApply
            ? "Drag onto a clip, or click to apply to the selected one"
            : "Drag onto a clip")
        .onAppear { shell.requestPreview(for: .filter(descriptor)) }
    }

    // ─── Layers ──────────────────────────────────────────────────────────────

    /// The lanes, in the order they draw — topmost first.
    private var layers: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            HStack {
                Text("\(shell.effects.tracks.count) tracks")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)

                Spacer()
            }

            if shell.effects.tracks.isEmpty {
                ComingSoon(
                    title: "No tracks",
                    detail: "Add an effect and a track appears to hold it.",
                    systemImage: "square.3.layers.3d",
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.tight) {
                        // Reversed so the topmost row is the one drawn last,
                        // which is how a layer list reads everywhere; document
                        // order would put the frontmost track at the bottom.
                        ForEach(shell.effects.tracks.reversed()) { track in
                            TrackRow(
                                name: track.name,
                                tint: track.tint,
                                effectCount: track.nodes.count,
                                isVisible: track.isVisible,
                                isLocked: track.isLocked,
                                isSelected: track.id == shell.selectedTrackID,
                                select: {
                                    shell.selectedTrackID = track.id
                                    shell.selectedNodeID = nil
                                },
                                toggleVisibility: { shell.toggleVisibility(of: track.id) },
                                toggleLock: { shell.toggleLock(of: track.id) },
                            )
                        }
                    }
                }
            }
        }
    }

}

// ─── Effect rows ─────────────────────────────────────────────────────────────

/// An effect and the presets that configure it, as one collapsible row.
private struct EffectGroup: View {
    let descriptor: EffectDescriptor
    let presets: [EffectPreset]
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let addBlank: () -> Void
    let addPreset: (EffectPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
            // An effect with no presets is a single row that places it. The
            // chevron and the count are there to manage a list; with nothing to
            // list they are a control that does nothing and a "0" beside it.
            EffectHeaderRow(
                name: descriptor.name,
                systemImage: descriptor.systemImage,
                presetCount: presets.isEmpty ? nil : presets.count,
                isExpanded: isExpanded,
                toggleExpanded: presets.isEmpty ? addBlank : toggleExpanded,
                add: addBlank,
            )

            if isExpanded {
                VStack(spacing: Theme.Spacing.hair) {
                    ForEach(presets) { preset in
                        PresetRow(name: preset.name, summary: preset.summary) { addPreset(preset) }
                    }
                }
                // Indented so the presets read as belonging to the effect above
                // rather than as siblings of it.
                .padding(.leading, Theme.Spacing.compact)
            }
        }
        .animation(Theme.Motion.quick, value: isExpanded)
    }
}

/// A pack of built effects, as one collapsible row.
///
/// Shaped like `EffectGroup` on purpose: a pack is browsed the same way an
/// effect's presets are, and giving it its own visual language would make two
/// things that behave alike look unrelated.
private struct PackGroup: View {
    let name: String
    let presets: [EffectPreset]
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let addPreset: (EffectPreset) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
            Button(action: toggleExpanded) {
                HStack(spacing: Theme.Spacing.snug) {
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Image(systemName: "shippingbox")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.secondary)
                        .frame(width: Theme.Size.ring * 2)

                    // No "Pack" subtitle: the heading above already says it,
                    // and a row that repeats its own group costs twice the
                    // height to say nothing new.
                    Text(name)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.primary)

                    Spacer(minLength: 0)

                    Text("\(presets.count)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }
                .padding(.horizontal, Theme.Spacing.compact)
                .frame(height: Theme.Size.control)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(isHovered ? Theme.Fill.rowHover : .clear)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            if isExpanded {
                VStack(spacing: Theme.Spacing.hair) {
                    ForEach(presets) { preset in
                        PresetRow(name: preset.name, summary: preset.summary) { addPreset(preset) }
                    }
                }
                .padding(.leading, Theme.Spacing.compact)
            }
        }
        .animation(Theme.Motion.quick, value: isExpanded)
    }
}

/// What the preset list is narrowed to.
private enum PresetFilter: Hashable {
    case effect(String)
    case pack(String)
}


