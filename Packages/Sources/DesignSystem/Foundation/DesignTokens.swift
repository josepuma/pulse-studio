import SwiftUI

/// The design system's vocabulary.
///
/// Every spacing, radius, size and duration in the app comes from here. Views
/// that reach for raw numbers drift apart as the app grows: this is what keeps
/// a timeline built next month looking like the transport bar built today.
public enum Theme {
    // ─── Spacing ─────────────────────────────────────────────────────────────

    /// A 4pt scale. Steps are named by role rather than size, so a value can be
    /// retuned across the app without renaming every call site.
    public enum Spacing {
        /// 2 — hairline gaps, icon to its own label.
        public static let hair: CGFloat = 2
        /// 4 — tightly related elements.
        public static let tight: CGFloat = 4
        /// 8 — within a control.
        public static let snug: CGFloat = 8
        /// 12 — between controls in a group.
        public static let compact: CGFloat = 12
        /// 16 — the default gap between elements.
        public static let regular: CGFloat = 16
        /// 24 — between groups.
        public static let loose: CGFloat = 24
        /// 32 — between sections.
        public static let section: CGFloat = 32
        /// 48 — page margins and hero areas.
        public static let page: CGFloat = 48
    }

    // ─── Radius ──────────────────────────────────────────────────────────────

    /// Corner radii, paired to the size of what they wrap. A radius that is too
    /// small on a large surface reads as a mistake rather than a style.
    public enum Radius {
        /// 8 — chips and small badges.
        public static let small: CGFloat = 8
        /// 12 — a clip on a timeline track.
        ///
        /// Its own step because a clip answers a question the others do not,
        /// and because the lane's corner is derived from this one rather than
        /// picked — a clip that changes shape carries the lane with it. At
        /// `bar` the corner is nearly half a clip's height and the block reads
        /// as a pill; much below this it goes hard.
        public static let clip: CGFloat = 12
        /// 10 — buttons and inline controls.
        public static let control: CGFloat = 10
        /// 16 — floating bars.
        public static let bar: CGFloat = 16
        /// 22 — cards and panels.
        ///
        /// Generous on purpose. Panels are told apart by tone rather than by a
        /// border now, and a large soft corner is what makes a solid block read
        /// as a surface rather than as a rectangle someone forgot to style.
        public static let panel: CGFloat = 22
        /// 22 — the canvas and other full-bleed surfaces.
        ///
        /// Matches `.panel` on purpose: the canvas sits beside the panels
        /// rather than on them, so a rounder corner on the one surface sharing
        /// their edge reads as belonging to a different family. It keeps its
        /// own name because it answers a different question — the two are equal
        /// today, not the same thing.
        public static let stage: CGFloat = 18

        /// The radius a shape needs to sit concentrically inside another.
        ///
        /// Two rounded rectangles are only parallel when the inner radius is
        /// the outer one less the gap between them. Pick the inner radius from
        /// the scale instead and the curves diverge: the inner corner reads as
        /// too square or too round against its own socket, which is the kind of
        /// wrongness that is obvious without being nameable.
        public static func nested(in outer: CGFloat, inset: CGFloat) -> CGFloat {
            max(outer - inset, 0)
        }
    }

    // ─── Sizing ──────────────────────────────────────────────────────────────

    public enum Size {
        /// The home screen's hero, as a share of the window's height. A share
        /// rather than points: the trailer is the page's subject, and fixed at
        /// one height it is a strip on a tall window and a wall on a short one.
        public static let heroShare: CGFloat = 0.78
        /// The least the hero shrinks to, so title and buttons always fit.
        public static let heroMinimum: CGFloat = 340
        /// How wide the hero's words may run before wrapping: past that a line
        /// crosses the subject of the picture it is laid over.
        public static let heroText: CGFloat = 520
        /// The narrowest a card on the home screen's grid gets. The grid fits
        /// as many columns as clear it and shares out the rest, so a 16:9
        /// thumbnail still shows a storyboard's art.
        public static let shelfCard: CGFloat = 300
        /// How far the first row of projects rides up into the hero's faded
        /// foot.
        public static let heroOverlap: CGFloat = 150
        /// 22 — dense icon button, for secondary actions in a crowded bar.
        public static let controlTiny: CGFloat = 22
        /// 28 — compact icon button.
        public static let controlSmall: CGFloat = 28
        /// 34 — standard icon button, the transport's play control.
        public static let control: CGFloat = 34
        /// 44 — primary action, and the minimum comfortable pointer target.
        public static let controlLarge: CGFloat = 44
        /// 1 — hairline separators, independent of screen scale.
        public static let hairline: CGFloat = 1
        /// 14 — height of a divider inside a bar.
        public static let dividerHeight: CGFloat = 14
        /// 10 — width of the playhead's grab handle.
        public static let playheadHandleWidth: CGFloat = 10
        /// 4 — thickness of a scrubber or slider groove.
        public static let grooveThickness: CGFloat = 4
        /// 1.5 — a ring drawn around a control, thicker than a hairline so it
        /// reads as a deliberate outline rather than an edge.
        public static let ring: CGFloat = 1.5
        /// 3 — thickness of the pill that marks the active tab or rail item.
        public static let indicator: CGFloat = 3
        /// 14 — length of that pill.
        ///
        /// Shorter than the item it marks on purpose: a bar the full width of
        /// a tab reads as an underline under its label, a short pill reads as
        /// a light switched on beneath it — the reference's language.
        public static let indicatorLength: CGFloat = 14
        /// 64 — a script's output row, about four lines before it scrolls.
        ///
        /// Deliberately small. Output shares a row with the ⌘S hint rather
        /// than taking a panel: a console occupying a third of the editor is
        /// one somebody closes, and the next error then goes unseen for the
        /// same reason the last one did.
        public static let scriptOutput: CGFloat = 64
        /// 78 — label column in an inspector row, wide enough for a two-word
        /// parameter name on one line ("Velocity Random", "Rotation Random").
        ///
        /// Sized to the names that exist rather than to the shortest: at 58 the
        /// two-word ones wrapped, and a wrapped label makes its row taller than
        /// its neighbours, which reads as uneven spacing rather than as a form.
        public static let propertyLabel: CGFloat = 78
        /// 38 — a numeric readout beside a slider, fixed so it stops jittering.
        public static let valueReadout: CGFloat = 38

        /// Heights for horizontal strips of content, such as the timeline.
        ///
        /// The canvas is what the app is for; anything stacked around it earns
        /// its height. These are deliberately tight.
        public enum Strip {
            /// 18 — a scannable summary, such as the whole-track overview.
            public static let overview: CGFloat = 18
            /// 40 — an interactive strip, such as the zoomable beat grid.
            public static let detail: CGFloat = 40
        }

        /// 22 — the column before an inspector label, where a property's
        /// stopwatch sits. Reserved on every row of a panel, animatable or
        /// not, so the labels line up.
        public static let keyframeGutter: CGFloat = controlTiny
        /// 22 — the column after an inspector field: the key at the playhead.
        /// Reserved for a whole group as soon as one of its rows animates, so
        /// the group's fields still line up with each other — and not before:
        /// held open while nothing animates, it left every field short of the
        /// group's edge for a diamond that was not there.
        ///
        /// One control wide, not three. Arrows either side of the diamond were
        /// tried: in a 264-point inspector they left the field 50 points — too
        /// narrow for "320 px" and its stepper. Moving between keys is on the
        /// diamond's menu and on the keyframe timeline's own arrows.
        public static let keyframeSlot: CGFloat = controlTiny

        /// 96 — the artwork band at the head of a card, tall enough for a few
        /// lines of a script to read as a picture.
        public static let cardArtwork: CGFloat = 96

        /// 28 — height of an inspector field.
        ///
        /// Two points more than it was: at 26 a column of fields read as a
        /// spreadsheet, and the inspector is moving to tabs, so it no longer
        /// has to fit every group on screen at once.
        public static let field: CGFloat = 28

        /// 44 — height of a floating control cluster.
        ///
        /// Every pill in a row shares this so they line up: letting each one
        /// take its height from its own contents leaves a ragged row, since a
        /// ringed button is taller than a line of text.
        public static let pill: CGFloat = 44

        /// 150 — the transport's scrub bar at rest.
        public static let scrubBar: CGFloat = 150
        /// 60 — the least the scrub bar shrinks to when the control row is
        /// short of width. It is the one control that can give way: text that
        /// does wraps inside a one-line pill.
        public static let scrubBarMinimum: CGFloat = 60

        /// 60 — one image in a picker grid: big enough to tell a flame from
        /// a wisp, small enough for five across a popover.
        public static let pickerTile: CGFloat = 60

        /// 18 — an image shown inside a field, beside its name.
        public static let fieldThumbnail: CGFloat = 18

        /// 380 × 440 — a picker popover: a search, a row of chips and a grid
        /// that scrolls, without covering the inspector it opens from.
        public static let pickerWidth: CGFloat = 380
        public static let pickerHeight: CGFloat = 440
    }

    // ─── Typography ──────────────────────────────────────────────────────────

    /// Roles rather than sizes: `.readout` says what the text is for, so the
    /// same numbers stay consistent everywhere they appear.
    public enum Typography {
        // Nunito, bundled (see `Fonts.swift`). Sized in points with
        // `relativeTo:` so text still follows the system's accessibility
        // scaling the way `.system(.caption)` did. Round terminals rather than
        // a plain grotesk: Geist was tried first and read as too neutral —
        // correct, and without character.

        /// The one title on a page that is a poster rather than a header — the
        /// featured project over its trailer. Large and heavy because it sits on
        /// moving pictures and has to hold its own against them. SemiBold, the
        /// heaviest cut bundled: a name that is not registered falls back to
        /// San Francisco without a word.
        public static let display = Font.custom(Theme.FontFace.semibold, size: 44, relativeTo: .largeTitle)
        /// A card's title on the home screen's shelf: a step above a row's,
        /// because it names a whole project under a picture, not an item in a
        /// list.
        public static let shelfTitle = Font.custom(Theme.FontFace.semibold, size: 15, relativeTo: .headline)
        /// Screen titles.
        public static let title = Font.custom(Theme.FontFace.semibold, size: 28, relativeTo: .largeTitle)
        /// Section headings.
        public static let heading = Font.custom(Theme.FontFace.semibold, size: 12, relativeTo: .subheadline)
        /// Card and row titles.
        public static let cardTitle = Font.custom(Theme.FontFace.medium, size: 13, relativeTo: .body)
        /// Body copy.
        public static let body = Font.custom(Theme.FontFace.regular, size: 12, relativeTo: .callout)
        /// Labels inside bars and chips.
        public static let label = Font.custom(Theme.FontFace.medium, size: 11, relativeTo: .caption)
        /// The smallest readable text: ruler ticks, secondary settings, the
        /// label under a tab's icon.
        public static let micro = Font.custom(Theme.FontFace.medium, size: 10, relativeTo: .caption2)
        /// Numbers that change every frame.
        ///
        /// Tabular digits rather than a monospaced face: the digits stop
        /// jittering, which is the only thing the monospace was for, and the
        /// colons and units keep the same face as the text around them.
        ///
        /// Nunito has no `tnum` feature and does not need one: its ten digits
        /// already share one advance (600 units, measured), so they are
        /// tabular by default. `monospacedDigit()` stays so the token keeps its
        /// promise if the face ever changes — `FontTests` checks the widths.
        public static let readout = Font.custom(Theme.FontFace.regular, size: 11, relativeTo: .caption)
            .monospacedDigit()
        /// The title of a group of fields — "TRANSFORM", "SOLID FILL".
        ///
        /// Small and set in capitals with a little tracking, so it reads as a
        /// label *for* the rows beneath rather than as one more row; a heading
        /// the size of the labels under it gives the group no top.
        public static let overline = Font.custom(Theme.FontFace.semibold, size: 10, relativeTo: .caption2)
        /// The letter spacing that goes with `overline`.
        public static let overlineTracking: CGFloat = 0.6
        /// Code, file paths and anything else that has to line up by column.
        public static let code = Font.custom(Theme.FontFace.mono, size: 11, relativeTo: .caption)
        /// Glyphs in icon buttons.
        ///
        /// The system font on purpose: these size SF Symbols, which are drawn
        /// to match San Francisco's metrics, not text.
        public static let controlIcon = Font.system(size: 15, weight: .regular)
        /// A large glyph standing in for empty state, such as a drop target.
        public static let emptyStateIcon = Font.system(size: 34, weight: .light)
    }

    // ─── Colour ──────────────────────────────────────────────────────────────

    /// Text and status colours.
    ///
    /// Text follows the system so the app respects appearance and accessibility
    /// settings; the accent and track colours are chosen rather than inherited,
    /// because the system palette desaturates in dark mode and content colours
    /// need to stay vivid against a near-black stage.
    public enum Palette {
        /// Primary text.
        public static let primary = Color.primary
        /// Supporting text and inactive glyphs.
        public static let secondary = Color.secondary
        /// The least prominent text, such as paths under a title.
        public static let tertiary = Color.secondary.opacity(0.7)
        /// The one colour that means *this one*: the active tab, the selected
        /// clip, a focused field, the primary action.
        ///
        /// **One accent, used for everything that is chosen.** There used to be
        /// three — a violet accent, an amber selection and an orange playhead —
        /// and three colours all saying "look here" say nothing.
        ///
        /// osu!'s own pink (#FF66AA): this is a storyboard editor for that
        /// game, and its brand colour is the one its players already read as
        /// "this is osu!". It was lime before, chosen as the hue furthest from
        /// every track tint; pink sits close to `TrackPalette.pink`, so a
        /// selected clip on a pink lane outlines in nearly its own colour. That
        /// was weighed and accepted — the lane palette is unchanged.
        public static let accent = Color(red: 1.0, green: 0.4, blue: 0.667)
        /// Text and glyphs drawn on the accent.
        ///
        /// Dark, not white: the pink is light enough that white on it loses
        /// contrast, and dark on it reads at a glance.
        public static let onAccent = Color(red: 0.05, green: 0.05, blue: 0.06)
        /// A softer accent for fills behind content.
        public static let accentMuted = Color(red: 1.0, green: 0.4, blue: 0.667).opacity(0.16)
        /// The playhead: a thin white line.
        ///
        /// White rather than the accent, so it never reads as one more chosen
        /// thing — a playhead is where you are, not what you picked — and white
        /// is the one colour no track or keyframe family uses.
        public static let playhead = Color.white
        /// The frame around a selected clip on the timeline.
        ///
        /// The accent itself. It used to be amber because the violet accent
        /// vanished on a violet lane. On a pink lane the osu! pink nearly does
        /// the same — a known, accepted cost (see `accent`). Kept as its own
        /// name because it answers its own question, and so a second colour
        /// can come back here if that cost stops being worth it.
        public static let selection = accent
        /// Something needs attention but still works.
        public static let warning = Color(red: 0.98, green: 0.68, blue: 0.25)
        /// Something failed.
        public static let danger = Color(red: 0.94, green: 0.36, blue: 0.40)
        /// Behind the storyboard canvas: osu! composites over black, and any
        /// other colour tints every partly transparent sprite.
        public static let stage = Color.black
    }

    /// Solid greys, darkest to lightest, that surfaces are built from.
    ///
    /// **Surfaces are told apart by tone, not by borders.** Translucent white
    /// over the chrome gave every panel a hairline to say where it ended, and a
    /// window of hairlines is busy before it holds anything. A step in tone does
    /// the same job silently — each surface is a little lighter than what it
    /// sits on.
    ///
    /// Solid rather than translucent so a surface looks the same wherever it is
    /// placed. State overlays (hover, selected) stay in ``Fill``, because those
    /// genuinely have to lighten whatever tone they land on.
    public enum Tone {
        /// The window itself, behind every panel.
        public static let base = Color(red: 0.039, green: 0.039, blue: 0.043)
        /// Anchored panels: side panel, inspector, timeline.
        public static let panel = Color(red: 0.082, green: 0.082, blue: 0.090)
        /// A block raised above a panel: popovers, cards, the selected row.
        public static let raised = Color(red: 0.118, green: 0.118, blue: 0.129)
        /// A control's well: fields, chips at rest, segment groups.
        public static let well = Color(red: 0.145, green: 0.145, blue: 0.157)
    }

    /// Translucent white fills, layered over the app's dark chrome.
    ///
    /// These are the states a control moves through — resting, hovered,
    /// selected — named so the whole app shifts together. Written as raw
    /// opacities they drift: the same control ends up at 0.12 in one place and
    /// 0.1 in another, and nobody notices until the two sit side by side.
    public enum Fill {
        /// 0.75 black — over the canvas outside the stage: still visible, so a
        /// sprite parked there can be found, but plainly not the picture.
        public static let offStage = Color.black.opacity(0.75)
        /// 0.03 — a block grouping other controls, barely distinct from behind.
        public static let subtle = Color.white.opacity(0.03)
        /// 0.05 — a panel anchored to the window: side panel, inspector, cards.
        ///
        /// Opaque rather than glass. A panel at the window edge has nothing
        /// behind it but the desktop, so refracting buys no depth and costs
        /// contrast on whatever it holds.
        public static let panel = Color.white.opacity(0.05)
        /// 0.09 — a panel lifted above its siblings.
        public static let raised = Color.white.opacity(0.09)
        /// 0.06 — the well a control sits in, at rest.
        public static let well = Color.white.opacity(0.06)
        /// 0.06 — a hovered control that is not selected.
        public static let hover = Color.white.opacity(0.06)
        /// 0.12 — the selected item in a group.
        public static let selected = Color.white.opacity(0.12)
        /// 0.025 — a hovered row tall enough that `.hover` would overwhelm it.
        public static let rowHover = Color.white.opacity(0.025)
        /// 0.05 — a selected row of that same height.
        ///
        /// Fainter than `.selected` because the fill covers several times the
        /// area: the same opacity over a track lane reads as a lit panel rather
        /// than as a highlighted row.
        public static let rowSelected = Color.white.opacity(0.05)
        /// 0.18 — a badge on tinted content, which needs more to read.
        public static let badge = Color.white.opacity(0.18)
        /// 0.18 — the unfilled groove of a scrubber or slider.
        ///
        /// Brighter than `.well` because these sit on the overlay's scrim
        /// rather than on the app's chrome, and a groove that reads as empty
        /// gives the filled part nothing to measure against.
        public static let groove = Color.white.opacity(0.18)
    }

    /// Hairline borders, in the same layered white.
    public enum Border {
        /// 0.04 — the edge of a field well; the tone step does most of the work.
        public static let field = Color.white.opacity(0.04)
        /// 0.04 — the edge of an anchored panel. Almost nothing: the panel
        /// already stands off the window by its tone.
        public static let panel = Color.white.opacity(0.04)
        /// 0.08 — the edge of a raised panel, which needs to separate further.
        public static let raised = Color.white.opacity(0.08)
        /// 0.1 — a card at rest.
        public static let card = Color.white.opacity(0.1)
        /// 0.28 — a card under the pointer.
        public static let cardHovered = Color.white.opacity(0.28)
        /// 0.2 — a badge over artwork.
        public static let badge = Color.white.opacity(0.2)
        /// 0.35 — the playhead's own edge.
        public static let handle = Color.white.opacity(0.35)
        /// 0.6 — the edge of the stage on the canvas: what osu! will draw.
        ///
        /// Strong on purpose. With the canvas showing what lies off the stage,
        /// this line is the only thing saying where the storyboard ends, and at
        /// a panel's 0.04 it disappeared against the black — reported as not
        /// being able to tell what would end up in the storyboard.
        public static let stage = Color.white.opacity(0.6)
    }

    /// Colours identifying content, chosen to stay distinct from each other
    /// and legible on a dark surface.
    ///
    /// A notch less saturated than they were, so the accent stays the loudest
    /// thing on screen: a selection frame has to win against the lane under it.
    /// Green leans cool (emerald), from when the accent was lime and a
    /// yellow-green lane read as half-selected. Pink is the lane that now sits
    /// nearest the accent.
    public enum TrackPalette {
        public static let blue = Color(red: 0.40, green: 0.60, blue: 0.92)
        public static let violet = Color(red: 0.60, green: 0.46, blue: 0.92)
        public static let pink = Color(red: 0.90, green: 0.46, blue: 0.70)
        public static let teal = Color(red: 0.30, green: 0.74, blue: 0.74)
        public static let amber = Color(red: 0.94, green: 0.68, blue: 0.32)
        public static let green = Color(red: 0.30, green: 0.74, blue: 0.56)
        public static let red = Color(red: 0.90, green: 0.44, blue: 0.44)
    }

    /// Colours for keyframe families, so nine rows of diamonds are not a wall.
    ///
    /// Drawn from ``TrackPalette`` rather than invented: the two sets sit in
    /// the same window, and a second family of near-but-not-quite colours is
    /// how a palette starts to drift.
    ///
    /// The assignment is not arbitrary — position and scale are the two most
    /// reached for, so they take the two most distinct hues.
    public enum KeyframePalette {
        public static let position = TrackPalette.blue
        public static let scale = TrackPalette.green
        public static let rotation = TrackPalette.amber
        public static let opacity = TrackPalette.violet
        public static let colour = TrackPalette.pink
        /// A filter's parameters, which have no family of their own.
        public static let filter = TrackPalette.teal

        /// The colour for a family, named by its raw value so the design
        /// system does not have to import the domain type.
        public static func colour(for family: String) -> Color {
            switch family {
            case "position": position
            case "scale": scale
            case "rotation": rotation
            case "opacity": opacity
            case "colour": colour
            default: filter
            }
        }
    }

    // ─── Motion ──────────────────────────────────────────────────────────────

    public enum Motion {
        /// Hover and focus feedback, fast enough to feel attached to the cursor.
        public static let quick = Animation.easeOut(duration: quickDuration)
        /// Panels appearing and disappearing.
        public static let standard = Animation.easeInOut(duration: standardDuration)
        /// Layout changes large enough to need following by eye.
        public static let deliberate = Animation.easeInOut(duration: deliberateDuration)

        // Durations, for the cases that have to wait one out rather than
        // animate. An `Animation` does not report its own length, so anything
        // scheduling around one needs the number itself — and reading it from
        // here is what keeps the wait and the animation in step.

        public static let quickDuration: TimeInterval = 0.12
        public static let standardDuration: TimeInterval = 0.22
        public static let deliberateDuration: TimeInterval = 0.35
    }

    // ─── Elevation ───────────────────────────────────────────────────────────

    /// Drop shadows that lift content off its surface.
    ///
    /// On a near-black stage a shadow reads as depth rather than as a grey
    /// smudge, which is what separates a floating block from a painted
    /// rectangle.
    public enum Elevation {
        public struct Shadow: Sendable {
            public let color: Color
            public let radius: CGFloat
            public let y: CGFloat
        }

        /// Content sitting on a panel: track blocks, chips.
        public static let low = Shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        /// Panels over the stage.
        public static let medium = Shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        /// Popovers and dragged content.
        public static let high = Shadow(color: .black.opacity(0.55), radius: 24, y: 8)
    }
}
