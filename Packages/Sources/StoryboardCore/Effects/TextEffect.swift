import Foundation

/// Text, drawn one sprite per character.
///
/// Per character and not per line, because that is what makes text animate:
/// letters arriving one after another, rising, spinning, scattering. A single
/// sprite holding a whole word can only move as a word — which is a caption,
/// not motion graphics.
///
/// The cost is real and worth naming: a line of forty characters is forty
/// sprites, and each one carries its own commands into the file. Long
/// paragraphs are not what this is for.
public struct TextEffect: Effect {
    public init() {}

    public enum Param {
        public static let text = "text"
        public static let font = "font"
        public static let size = "size"
        public static let bold = "bold"
        public static let italic = "italic"
        public static let tracking = "tracking"
        public static let lineHeight = "lineHeight"
        public static let orientation = "orientation"
        public static let latin = "latin"
        public static let color = "color"
        public static let additive = "additive"
        public static let stagger = "stagger"
        public static let staggerFrom = "staggerFrom"
        public static let fadeIn = "fadeIn"
        public static let fadeOut = "fadeOut"
        public static let riseFrom = "riseFrom"
        public static let driftFrom = "driftFrom"
        public static let easing = "easing"
        public static let exit = "exit"
        public static let exitForce = "exitForce"
        public static let driftX = "driftX"
        public static let driftY = "driftY"
        public static let scaleFrom = "scaleFrom"
        public static let spinFrom = "spinFrom"
        public static let unit = "unit"
        public static let waveAmount = "waveAmount"
        public static let staggerMode = "staggerMode"
        public static let staggerSpread = "staggerSpread"
        public static let scatterX = "scatterX"
        public static let scatterY = "scatterY"
        public static let scatterRotation = "scatterRotation"
        public static let scatterScale = "scatterScale"
        public static let stretchFromX = "stretchFromX"
        public static let stretchFromY = "stretchFromY"
        public static let pivot = "pivot"
        public static let exitStagger = "exitStagger"
        public static let exitOrder = "exitOrder"
        public static let outRise = "outRise"
        public static let outDrift = "outDrift"
        public static let outScale = "outScale"
        public static let outSpin = "outSpin"
        public static let outStretchX = "outStretchX"
        public static let outStretchY = "outStretchY"
        public static let outScatter = "outScatter"
        public static let outScatterRotation = "outScatterRotation"
        public static let outEasing = "outEasing"
        public static let colourMode = "colourMode"
        public static let colour2 = "colour2"
        public static let gradientAcross = "gradientAcross"
        public static let sweepOrder = "sweepOrder"
        public static let sweepStart = "sweepStart"
        public static let sweepLength = "sweepLength"
        public static let sweepEdge = "sweepEdge"
        public static let flash = "flash"
        public static let holdMotion = "holdMotion"
        public static let holdAmount = "holdAmount"
        public static let holdBreathe = "holdBreathe"
        public static let holdSpeed = "holdSpeed"
        public static let holdPhase = "holdPhase"
    }

    /// The stream In Scatter draws from, derived from each glyph's own.
    ///
    /// Its own stream rather than the glyph's: Explode and Drift already draw
    /// from that one, and four more draws ahead of them would hand every saved
    /// burst a different set of headings.
    static let scatterTag = 0x5CA7

    public static let descriptor = EffectDescriptor(
        type: "text",
        name: "Text",
        category: .generate,
        systemImage: "textformat",
        parameters: [
            EffectParameter(
                id: Param.text, name: "Text", group: "Content",
                defaultValue: .text("HELLO"),
            ),
            EffectParameter(
                id: Param.font, name: "Font", group: "Content",
                defaultValue: .text("Helvetica"),
            ),
            EffectParameter(
                id: Param.size, name: "Size", group: "Content",
                defaultValue: .number(48), range: 8...400, step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.bold, name: "Bold", group: "Content",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: Param.italic, name: "Italic", group: "Content",
                defaultValue: .toggle(false),
            ),

            EffectParameter(
                id: Param.tracking, name: "Tracking", group: "Layout",
                defaultValue: .number(0), range: -40...200, step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.lineHeight, name: "Line Height", group: "Layout",
                defaultValue: .number(1.2), range: 0.5...4, step: 0.05,
            ),
            EffectParameter(
                id: Param.orientation, name: "Orientation", group: "Layout",
                defaultValue: .choice(Orientation.horizontal.rawValue),
                options: Orientation.allCases.map(\.rawValue),
            ),
            EffectParameter(
                id: Param.latin, name: "Latin", group: "Layout",
                defaultValue: .choice(Latin.rotated.rawValue),
                options: Latin.allCases.map(\.rawValue),
                // Only a vertical line has a choice to make about it.
                shownWhen: .init(parameter: Param.orientation, isAnyOf: [Orientation.vertical.rawValue]),
            ),
            // Colour sits with the content rather than the animation: what
            // colour the words are is a property of the words.
        ] + TextColour.parameters + [
            // Every animation parameter rests at nothing.
            //
            // Dropping a text effect gives text, not a performance: a stagger
            // and a fade nobody asked for is animation appearing out of a
            // placement, and it has to be found and switched off before the
            // plain case can be had. The presets are where the moves live —
            // the same rule a placed effect already follows elsewhere.
            //
            // Grouped by the question each answers — in what order, how it
            // arrives, how loose, how it holds and leaves — instead of one
            // "Animation" block thirty rows long. The groups are only labels:
            // moving a parameter between them touches no stored value.

            // ─── Sequence ────────────────────────────────────────────────────
            // What arrives together, and in what order.
            EffectParameter(
                id: Param.unit, name: "Unit", group: "Sequence",
                defaultValue: .choice("Character"),
                options: ["Character", "Word", "Line"],
            ),
            EffectParameter(
                id: Param.staggerFrom, name: "Stagger From", group: "Sequence",
                defaultValue: .choice("Start"),
                options: ["Start", "End", "Centre", "Random", "Edges", "Wave"],
            ),
            EffectParameter(
                id: Param.waveAmount, name: "Wave Amount", group: "Sequence",
                defaultValue: .number(1), range: 0...3, step: 0.1,
                shownWhen: .init(parameter: Param.staggerFrom, isAnyOf: ["Wave"]),
            ),
            EffectParameter(
                id: Param.staggerMode, name: "Stagger Mode", group: "Sequence",
                defaultValue: .choice("Per Unit"),
                options: ["Per Unit", "Spread"],
            ),
            EffectParameter(
                id: Param.stagger, name: "Stagger", group: "Sequence",
                defaultValue: .number(0), range: 0...1000, step: 5, unit: "ms",
                shownWhen: .init(parameter: Param.staggerMode, isAnyOf: ["Per Unit"]),
            ),
            EffectParameter(
                id: Param.staggerSpread, name: "Spread", group: "Sequence",
                defaultValue: .number(60), range: 0...100, step: 1, unit: "%",
                shownWhen: .init(parameter: Param.staggerMode, isAnyOf: ["Spread"]),
            ),

            // ─── Entrance ────────────────────────────────────────────────────
            EffectParameter(
                id: Param.fadeIn, name: "Fade In", group: "Entrance",
                defaultValue: .number(0), range: 0...5000, step: 10, unit: "ms",
            ),
            // The curve is what separates a fall from a drop, a slide from a
            // snap. Fixed at one ease, every preset reads the same however its
            // numbers differ.
            EffectParameter(
                id: Param.easing, name: "Easing", group: "Entrance",
                defaultValue: .choice("Ease Out"),
                options: ["Linear", "Ease Out", "Back", "Elastic", "Bounce", "Expo"],
            ),
            EffectParameter(
                id: Param.riseFrom, name: "Rise From", group: "Entrance",
                defaultValue: .number(0), range: -400...400, step: 1, unit: "px",
            ),
            // Horizontal as well as vertical, so letters can sweep in from a
            // side rather than only from above or below. One axis alone makes
            // every entrance a variation of the same move.
            EffectParameter(
                id: Param.driftFrom, name: "Drift From", group: "Entrance",
                defaultValue: .number(0), range: -800...800, step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.scaleFrom, name: "Scale From", group: "Entrance",
                defaultValue: .number(1), range: 0...5, step: 0.05,
            ),
            EffectParameter(
                id: Param.spinFrom, name: "Spin From", group: "Entrance",
                defaultValue: .number(0), range: -720...720, step: 5, unit: "°",
            ),
            // One axis squashed is a card turning or a letter unfolding, which
            // a uniform scale cannot say. At 1 they write nothing.
            EffectParameter(
                id: Param.stretchFromX, name: "Stretch From X", group: "Entrance",
                defaultValue: .number(1), range: 0...5, step: 0.05,
            ),
            EffectParameter(
                id: Param.stretchFromY, name: "Stretch From Y", group: "Entrance",
                defaultValue: .number(1), range: 0...5, step: 0.05,
            ),
            // What a glyph scales and turns about. Bottom is the bottom edge
            // of the glyph's texture box, not the typographic baseline: the
            // box is what a sprite's origin can name, and it holds the same
            // place in every glyph of a style, so a line still sits level.
            EffectParameter(
                id: Param.pivot, name: "Pivot", group: "Entrance",
                defaultValue: .choice("Centre"),
                options: ["Centre", "Bottom"],
            ),

            // ─── Scatter ─────────────────────────────────────────────────────
            // Where each glyph starts from, jittered on its own. Rise and Drift
            // move the whole line the same way; scatter is what makes letters
            // assemble out of a cloud rather than slide in as a block.
            EffectParameter(
                id: Param.scatterX, name: "Scatter X", group: "Scatter",
                defaultValue: .number(0), range: 0...800, step: 5, unit: "px",
            ),
            EffectParameter(
                id: Param.scatterY, name: "Scatter Y", group: "Scatter",
                defaultValue: .number(0), range: 0...600, step: 5, unit: "px",
            ),
            EffectParameter(
                id: Param.scatterRotation, name: "Scatter Rotation", group: "Scatter",
                defaultValue: .number(0), range: 0...360, step: 5, unit: "°",
            ),
            EffectParameter(
                id: Param.scatterScale, name: "Scatter Scale", group: "Scatter",
                defaultValue: .number(0), range: 0...3, step: 0.05,
            ),
        ] + TextHoldMotion.parameters + TextExit.parameters + TextGlyphParticles.parameters,
    )

    /// Which way a line runs.
    public enum Orientation: String, CaseIterable, Sendable {
        case horizontal = "Horizontal"
        /// 縦書き: top to bottom, each line a column, columns right to left.
        case vertical = "Vertical"
    }

    /// How Latin letters and digits stand in a vertical line.
    public enum Latin: String, CaseIterable, Sendable {
        /// On their side, as vertical Japanese sets running Latin.
        case rotated = "Rotated"
        /// Standing, drawn as horizontal text — a short acronym or a number.
        case upright = "Upright"
    }

    /// The static descriptor, with `Sung` offered where it would do something.
    ///
    /// Only on a clip that carries sung timing *and* whose text still matches
    /// it: an option that silently falls back is a control that lies.
    public func descriptor(for node: EffectNode) -> EffectDescriptor {
        var resolved = Self.descriptor
        guard let sung = node.sungWords,
              case .text(let text)? = node.values[Param.text],
              SungTiming.fits(sung, text: text)
        else { return resolved }
        resolved.parameters = resolved.parameters.map { parameter in
            guard parameter.id == Param.staggerMode || parameter.id == Param.sweepOrder else { return parameter }
            var offered = parameter
            offered.options.append(SungTiming.choice)
            return offered
        }
        return resolved
    }

    public func evaluate(in context: EffectContext, rng: inout EffectRandom) -> [StoryboardSprite] {
        let content = context.text(Param.text)
        guard !content.isEmpty, context.duration > 0 else { return [] }

        let style = TextStyle(
            font: context.text(Param.font),
            size: context.number(Param.size),
            isBold: context.toggle(Param.bold),
            isItalic: context.toggle(Param.italic),
        )

        let placed = layout(content, style: style, context: context)
        guard !placed.isEmpty else { return [] }

        let units: [Int] = switch context.choice(Param.unit) {
        case "Word": placed.map(\.word)
        case "Line": placed.map(\.line)
        default: Array(placed.indices)
        }
        // When each glyph was sung, if the clip knows and its text still
        // matches; otherwise `Sung` falls back to what it was before.
        let sungTimes: [Double]? = if let sung = context.node.sungWords, SungTiming.fits(sung, text: content) {
            SungTiming.glyphTimes(sung, unit: context.choice(Param.unit), lines: placed.map(\.line))
                .map { min(max(0, $0), context.duration) }
        } else {
            nil
        }

        let ranks = TextStagger.ranks(
            units: units,
            order: context.choice(Param.staggerFrom),
            waveAmount: context.number(Param.waveAmount),
            rng: &rng,
        )
        // Who leaves when. Nothing to stagger without a fade-out: the glyph
        // has no exit to move.
        let fadeOut = max(0, context.number(Param.fadeOut))
        let exitDelays = fadeOut > 0
            ? TextExit.delays(
                entranceRanks: ranks,
                units: units,
                order: context.choice(Param.exitOrder),
                stagger: max(0, context.number(Param.exitStagger)),
                rng: rng,
            )
            : ranks.map { _ in 0 }
        let latestExit = exitDelays.max() ?? 0
        // The room a stagger can use: what is left once the entrance has run
        // and the exit has made room for itself — its staggered start
        // included, so every glyph has landed before the first one leaves.
        let window = max(
            0,
            context.duration - max(0, context.number(Param.fadeIn)) - fadeOut
                - (latestExit > 0 ? latestExit : 0),
        )
        let mode = context.choice(Param.staggerMode)
        let delays = if mode == SungTiming.choice, let sungTimes {
            sungTimes
        } else {
            TextStagger.delays(
                ranks: ranks,
                mode: mode == SungTiming.choice ? "Per Unit" : mode,
                stagger: max(0, context.number(Param.stagger)),
                spread: context.number(Param.staggerSpread),
                window: window,
            )
        }

        let holdStream = rng.stream(TextHoldMotion.tag)
        let colours = TextColour.plan(placed.map { ($0.x, $0.line) }, units: units, sung: sungTimes, context: context, rng: rng)
        let plans = placed.indices.map { index in
            GlyphPlan(
                delay: delays[index], exitDelay: exitDelays[index], unit: units[index],
                colour: colours[index].colour, highlightAt: colours[index].highlightAt,
                hold: holdStream.stream(units[index]),
            )
        }

        let letters = placed.enumerated().map { index, glyph -> StoryboardSprite in
            // A stream per character, so raising the count adds letters rather
            // than reshuffling the ones already placed.
            var stream = rng.stream(index)
            return sprite(
                glyph,
                index: index,
                plan: plans[index],
                style: style,
                context: context,
                rng: &stream,
            )
        }

        // After every letter, so a burst draws over the line it comes from and
        // the letters keep the draw order they always had.
        let fadeIn = max(0, context.number(Param.fadeIn))
        let particles = TextGlyphParticles.sprites(
            for: placed.indices.map { index in
                let span = Span(plan: plans[index], duration: context.duration, fadeIn: fadeIn, fadeOut: fadeOut)
                return TextGlyphParticles.Glyph(
                    index: index, sprite: letters[index],
                    birth: span.birth, landed: span.landed, exitStart: span.exitStart,
                    life: span.life, hasExit: span.hasExit,
                    halfWidth: placed[index].size.width / 2, halfHeight: placed[index].size.height / 2,
                )
            },
            context: context,
            rng: rng,
        )
        return letters + particles
    }

    // ─── Layout ──────────────────────────────────────────────────────────────

    /// One character with the place it occupies, relative to the clip's centre.
    private struct PlacedGlyph {
        var character: Character
        var x: Double
        var y: Double
        /// Dense indices of the word and the line this glyph belongs to.
        /// Dense, because End, Centre and Spread read the highest one — a
        /// blank line or a run of spaces must not leave gaps in the count.
        var word: Int
        var line: Int
        /// The glyph's own metrics, which size its texture box.
        var size: TextMetrics.Glyph
        /// The style it is drawn in: in a vertical line, upright Latin is
        /// drawn as horizontal text while everything else uses vertical forms.
        var style: TextStyle
    }

    /// Lays the text out around its own centre.
    ///
    /// Around the centre rather than from a corner, because the clip's
    /// transform turns and scales about that point — text laid out from a
    /// corner would swing around one end when rotated.
    private func layout(
        _ content: String,
        style: TextStyle,
        context: EffectContext,
    ) -> [PlacedGlyph] {
        if context.choice(Param.orientation) == Orientation.vertical.rawValue {
            return layoutVertical(content, style: style, context: context)
        }
        let tracking = context.number(Param.tracking)
        let lineHeight = style.size * context.number(Param.lineHeight)

        let lines = content.components(separatedBy: "\n")
        var placed: [PlacedGlyph] = []

        // Measured first so each line can be justified against its own width.
        let widths = lines.map { line in
            line.reduce(0.0) { $0 + TextMetrics.glyph($1, style: style).width + tracking }
                - (line.isEmpty ? 0 : tracking)
        }

        var word = -1
        var lineIndex = -1
        let blockHeight = lineHeight * Double(lines.count)
        let originY = -blockHeight / 2 + lineHeight / 2

        for (row, line) in lines.enumerated() {
            // Centred on the clip, which is also what the transform turns
            // about. There is no alignment control: it would need more than one
            // line to mean anything, and the field holds one.
            var cursor = -widths[row] / 2
            var inWord = false
            var lineStarted = false

            for character in line {
                let glyph = TextMetrics.glyph(character, style: style)
                // Spaces take their width and draw nothing.
                if character.isWhitespace {
                    inWord = false
                } else {
                    // Punctuation is not whitespace, so it stays with its word.
                    if !inWord { word += 1; inWord = true }
                    if !lineStarted { lineIndex += 1; lineStarted = true }
                    // Centred on the advance, which is what the texture spans:
                    // the glyph's own drawing sits inside that box wherever the
                    // font puts it, and moving the sprite to the ink's centre
                    // instead would undo the spacing the font describes.
                    placed.append(PlacedGlyph(
                        character: character,
                        x: cursor + glyph.width / 2,
                        y: originY + lineHeight * Double(row),
                        word: word,
                        line: lineIndex,
                        size: glyph,
                        style: style,
                    ))
                }
                cursor += glyph.width + tracking
            }
        }

        return placed
    }

    /// Lays the text out in columns (縦書き): each line top to bottom, the
    /// lines right to left, the block centred on the clip like horizontal
    /// text so the transform still turns it about its middle.
    ///
    /// The font does the hard part: a vertical style draws `、` and small kana
    /// in their corner, `ー` and brackets turned and Latin on its side, all
    /// inside each glyph's own texture. A glyph's box is measured down the
    /// column — `width` across it, `height` the advance — so the same
    /// `TextSprite.boxHeight` still says where the bottom of a texture is.
    private func layoutVertical(
        _ content: String,
        style: TextStyle,
        context: EffectContext,
    ) -> [PlacedGlyph] {
        let tracking = context.number(Param.tracking)
        let columnPitch = style.size * context.number(Param.lineHeight)
        var vertical = style
        vertical.isVertical = true
        let upright = context.choice(Param.latin) == Latin.upright.rawValue

        // Kana, kanji and full-width punctuation have vertical forms; a
        // character entirely below the CJK blocks is Latin-like.
        func glyphStyle(_ character: Character) -> TextStyle {
            let latin = character.unicodeScalars.allSatisfy { $0.value < 0x2E80 }
            return upright && latin ? style : vertical
        }
        // Down the column: a vertical box's height is its advance; an
        // upright Latin glyph, set horizontally, takes its own height.
        func advance(_ character: Character) -> Double {
            TextMetrics.glyph(character, style: glyphStyle(character)).height
        }

        let lines = content.components(separatedBy: "\n")
        let lengths = lines.map { line in
            line.reduce(0.0) { $0 + advance($1) + tracking } - (line.isEmpty ? 0 : tracking)
        }
        // The first column is the rightmost.
        let firstX = columnPitch * Double(lines.count - 1) / 2

        var placed: [PlacedGlyph] = []
        var word = -1
        var lineIndex = -1
        for (column, line) in lines.enumerated() {
            var cursor = -lengths[column] / 2
            var inWord = false
            var lineStarted = false
            for character in line {
                let glyphStyle = glyphStyle(character)
                let glyph = TextMetrics.glyph(character, style: glyphStyle)
                if character.isWhitespace {
                    inWord = false
                } else {
                    if !inWord { word += 1; inWord = true }
                    if !lineStarted { lineIndex += 1; lineStarted = true }
                    placed.append(PlacedGlyph(
                        character: character,
                        x: firstX - columnPitch * Double(column),
                        y: cursor + glyph.height / 2,
                        word: word,
                        line: lineIndex,
                        size: glyph,
                        style: glyphStyle,
                    ))
                }
                cursor += glyph.height + tracking
            }
        }
        return placed
    }

    /// The curve an entrance travels on.
    ///
    /// Named rather than exposed as the full easing list: these are the six
    /// that read as distinct movements, and a picker of thirty-five curves is a
    /// reference table rather than a choice.
    private static func easing(named name: String) -> Easing {
        switch name {
        case "Linear": .linear
        case "Back": .backOut
        case "Elastic": .elasticOut
        case "Bounce": .bounceOut
        case "Expo": .expoOut
        default: .out
        }
    }

    // ─── One character ───────────────────────────────────────────────────────

    /// What `evaluate` decides for a glyph before any of its commands exist:
    /// when it arrives, how much earlier than the clip's end it leaves, which
    /// unit it moves with, its colour, and the stream its hold draws from.
    struct GlyphPlan {
        var delay: Double
        var exitDelay: Double
        var unit: Int
        var colour: EffectColor
        var highlightAt: Double?
        /// The hold's stream, one per unit, so a word trembles as one.
        var hold: EffectRandom
    }

    /// The moments one glyph's stages share.
    ///
    /// One place, because the fade, the travel and the exit all need the same
    /// answer — three copies of it is how one of them ends up a few hundred
    /// milliseconds off.
    struct Span {
        /// When the glyph starts arriving.
        let birth: Double
        /// When its entrance has finished.
        let landed: Double
        /// When it starts leaving.
        let exitStart: Double
        /// When it is gone: the end of its own exit, or the clip's end if it
        /// has none.
        let life: Double
        let hasExit: Bool

        /// When *this* character leaves — never before it has finished
        /// arriving.
        ///
        /// `birth` carries the stagger and so differs per character, while the
        /// clip's end is the same for all of them. Taken as `end - fadeOut`
        /// alone, every character's fade-out fired at the same moment while
        /// the late ones were still fading in — two commands fighting over
        /// opacity, which osu! settles by letting the last one written win.
        /// Measured on `cascade` over sixteen characters in a two-second clip:
        /// fade-outs at 1500 against fade-ins running to 2350.
        ///
        /// A character that cannot both arrive and leave inside the clip keeps
        /// its arrival and loses the exit: appearing and then vanishing is
        /// still the line being read, while a fade-out over an unfinished
        /// fade-in is a glyph that flickers and never lands.
        ///
        /// An exit delay moves this glyph's whole exit earlier, so later ones
        /// can leave after it; with no fade-out there is nothing to move.
        init(plan: GlyphPlan, duration: Double, fadeIn: Double, fadeOut: Double) {
            birth = plan.delay
            landed = birth + fadeIn
            let end = max(landed, duration - (fadeOut > 0 ? plan.exitDelay : 0))
            exitStart = max(landed, end - fadeOut)
            hasExit = fadeOut > 0 && exitStart < end
            life = hasExit ? end : duration
        }

        /// Where the glyph stops holding: its exit, or the end of its life.
        var holdEnd: Double { hasExit ? exitStart : life }
    }

    /// One glyph, written in stages: opacity, entrance, hold, exit, colour.
    ///
    /// The order the stages append in is the order the commands are written,
    /// and saved output depends on it — a stage moved is a file that diffs.
    private func sprite(
        _ glyph: PlacedGlyph,
        index: Int,
        plan: GlyphPlan,
        style: TextStyle,
        context: EffectContext,
        rng: inout EffectRandom,
    ) -> StoryboardSprite {
        let fadeIn = max(0, context.number(Param.fadeIn))
        let fadeOut = max(0, context.number(Param.fadeOut))
        let span = Span(plan: plan, duration: context.duration, fadeIn: fadeIn, fadeOut: fadeOut)

        // Bottom moves the anchor down by half the box and the position with
        // it, so a glyph at rest is drawn exactly where Centre draws it: only
        // what it scales and turns about changes. Every move below is relative
        // to `defaultY`, so rises and falls travel the same distance.
        let onBottom = context.choice(Param.pivot) == "Bottom"
        let centreY = TransformProperty.y.defaultValue + glyph.y
        var sprite = StoryboardSprite(
            id: "\(context.idPrefix)/c\(index)",
            layer: .foreground,
            origin: onBottom ? .bottomCentre : .centre,
            filePath: TextSprite.path(for: glyph.character, style: glyph.style),
            defaultX: TransformProperty.x.defaultValue + glyph.x,
            defaultY: onBottom ? centreY + TextSprite.boxHeight(glyph.size, style: glyph.style) / 2 : centreY,
        )

        sprite.commands += opacity(span, fadeIn: fadeIn, fadeOut: fadeOut)

        let scatter = Scatter(context: context, stream: rng.stream(Self.scatterTag))
        // A stretched sprite speaks `_V` for its whole life, exit included.
        //
        // osu! keeps `S` and `V` as two properties that multiply, while the
        // editor's resolver lets a `V` track override `S` outright: a sprite
        // holding both draws one way here and another in the game. One
        // vocabulary per sprite is what keeps the preview and the file in
        // agreement, and plain `_S` stays where nothing is stretched — one
        // number where a vector would cost two.
        let exit = context.choice(Param.exit)
        let stretchX = context.number(Param.stretchFromX)
        let stretchY = context.number(Param.stretchFromY)
        let outStretch: (x: Double, y: Double) = switch exit {
        case "Custom": (context.number(Param.outStretchX), context.number(Param.outStretchY))
        case "Mirror In": (stretchX, stretchY)
        default: (1, 1)
        }
        let usesVector = (fadeIn > 0 && (stretchX != 1 || stretchY != 1))
            || (fadeOut > 0 && (outStretch.x != 1 || outStretch.y != 1))
        sprite.commands += entrance(
            span, at: (sprite.defaultX, sprite.defaultY), scatter: scatter, vector: usesVector, context: context,
        )

        // The travel, over the span the character is actually up: after its own
        // entrance has landed and before the exit takes over. Sharing those
        // spans would have two commands writing the same position, and the
        // later one simply wins.
        //
        // A hold that moves the glyph carries the travel in its own steps, so
        // there is one position command at a time.
        let travel = (x: context.number(Param.driftX), y: context.number(Param.driftY))
        let hold = TextHoldMotion.Settings(context: context)
        if let steps = TextHoldMotion.position(
            hold, unit: plan.unit, rest: (sprite.defaultX, sprite.defaultY), travel: travel,
            start: span.landed, end: span.holdEnd, rng: plan.hold,
        ) {
            sprite.commands += steps
        } else if travel.x != 0 || travel.y != 0, span.holdEnd > span.landed {
            sprite.commands.append(Command(
                easing: .linear, startTime: span.landed, endTime: span.holdEnd,
                payload: .move(
                    startX: sprite.defaultX,
                    startY: sprite.defaultY,
                    endX: sprite.defaultX + travel.x,
                    endY: sprite.defaultY + travel.y,
                ),
            ))
        }

        sprite.commands += TextHoldMotion.scale(
            hold, unit: plan.unit, start: span.landed, end: span.holdEnd, vector: usesVector,
        )

        // The exit, which mirrors whichever entrance was chosen — text that
        // arrives with character and then merely dissolves is half a move.
        // From wherever the travel left it, or the character snaps back to
        // its starting place before leaving.
        let from = (x: sprite.defaultX + travel.x, y: sprite.defaultY + travel.y)
        if span.hasExit, TextExit.parametricNames.contains(exit) {
            sprite.commands += TextExit.parametric(
                exitTarget(exit, scatter: scatter, outStretch: outStretch, context: context, rng: rng),
                from: from, start: span.exitStart, end: span.life, vector: usesVector,
            )
        } else if span.hasExit {
            sprite.commands += TextExit.legacy(
                exit,
                start: span.exitStart,
                end: span.life,
                from: from,
                offset: (glyph.x, glyph.y),
                force: context.number(Param.exitForce),
                vector: usesVector,
                rng: &rng,
            )
        }

        // Tinted rather than drawn in colour: the glyph texture is white, so
        // one image serves every colour it is used in.
        sprite.commands += TextColour.commands(
            base: plan.colour,
            highlight: plan.highlightAt.map { (context.color(Param.colour2), $0) },
            edge: max(0, context.number(Param.sweepEdge)),
            flash: context.toggle(Param.flash),
            birth: span.birth,
            life: span.life,
        )

        if context.toggle(Param.additive) {
            sprite.commands.append(Command(
                easing: .linear, startTime: span.birth, endTime: span.life,
                payload: .parameter(.additive),
            ))
        }

        return sprite
    }

    /// Opacity first, and always present: without a fade the sprite holds its
    /// default from the start of the file, so every character would be
    /// visible before its own stagger reached it.
    private func opacity(_ span: Span, fadeIn: Double, fadeOut: Double) -> [Command] {
        var commands: [Command] = []
        if fadeIn > 0 {
            commands.append(Command(
                easing: .out, startTime: span.birth, endTime: span.landed,
                payload: .fade(start: 0, end: 1),
            ))
            // Held from arrival to whenever this character leaves. Without
            // the hold a sprite lives only for its own fade — a character
            // that appears and then stops existing — and a character whose
            // exit was dropped for want of room needs it to reach its end.
            if !span.hasExit || fadeOut == 0 {
                commands.append(Command(
                    easing: .linear, startTime: span.landed, endTime: span.life,
                    payload: .fade(start: 1, end: 1),
                ))
            }
        } else {
            // No fade still means visible: without a command the sprite holds
            // its default opacity from the beginning of the file, so every
            // character would be on screen before its own stagger reached it.
            commands.append(Command(
                easing: .linear, startTime: span.birth, endTime: fadeOut > 0 ? span.birth : span.life,
                payload: .fade(start: 1, end: 1),
            ))
        }
        // Only when there is room for it after the character has arrived.
        if span.hasExit {
            commands.append(Command(
                easing: .linear, startTime: span.exitStart, endTime: span.life,
                payload: .fade(start: 1, end: 0),
            ))
        }
        return commands
    }

    /// The entrance: each character travels from wherever it was told to
    /// start to where the layout puts it, over its own fade-in.
    private func entrance(
        _ span: Span,
        at rest: (x: Double, y: Double),
        scatter: Scatter,
        vector: Bool,
        context: EffectContext,
    ) -> [Command] {
        guard span.landed > span.birth else { return [] }
        var commands: [Command] = []
        let curve = Self.easing(named: context.choice(Param.easing))
        let rise = context.number(Param.riseFrom)
        let drift = context.number(Param.driftFrom)

        // Both axes in one command when both move: `_M` carries the pair, and
        // two separate commands would each fight for the same position.
        if rise != 0 || drift != 0 || scatter.x != nil || scatter.y != nil {
            commands.append(Command(
                easing: curve, startTime: span.birth, endTime: span.landed,
                payload: .move(
                    startX: Scatter.adding(scatter.x, to: rest.x + drift),
                    startY: Scatter.adding(scatter.y, to: rest.y + rise),
                    endX: rest.x,
                    endY: rest.y,
                ),
            ))
        }

        let scaleFrom = context.number(Param.scaleFrom)
        // The entrance's own stretch asks for a command; a stretch that only
        // the exit has makes it `_V` without making it move.
        let stretched = context.number(Param.stretchFromX) != 1 || context.number(Param.stretchFromY) != 1
        if scaleFrom != 1 || scatter.scale != nil || stretched {
            let start = Self.startScale(scaleFrom, scatter: scatter)
            commands.append(Command(
                easing: curve, startTime: span.birth, endTime: span.landed,
                payload: vector
                    ? .vectorScale(
                        startX: start * context.number(Param.stretchFromX),
                        startY: start * context.number(Param.stretchFromY),
                        endX: 1, endY: 1,
                    )
                    : .scale(start: start, end: 1),
            ))
        }

        let spin = context.number(Param.spinFrom)
        if spin != 0 || scatter.rotation != nil {
            commands.append(Command(
                easing: curve, startTime: span.birth, endTime: span.landed,
                payload: .rotate(start: Scatter.adding(scatter.rotation, to: spin) * .pi / 180, end: 0),
            ))
        }
        return commands
    }

    /// Where a Custom or Mirror In exit takes this glyph.
    ///
    /// Mirror In is the entrance played backwards: the glyph returns to the
    /// very place, scale and turn it arrived from — its own scatter included,
    /// so letters that assembled out of a cloud go back into it — on the
    /// entrance curve's mirror. Custom reads its own axes, with a scatter of
    /// its own drawn in a fixed order from a derived stream.
    private func exitTarget(
        _ exit: String,
        scatter: Scatter,
        outStretch: (x: Double, y: Double),
        context: EffectContext,
        rng: EffectRandom,
    ) -> TextExit.Target {
        if exit == "Mirror In" {
            return TextExit.Target(
                dx: Scatter.adding(scatter.x, to: context.number(Param.driftFrom)),
                dy: Scatter.adding(scatter.y, to: context.number(Param.riseFrom)),
                scale: Self.startScale(context.number(Param.scaleFrom), scatter: scatter),
                stretchX: outStretch.x,
                stretchY: outStretch.y,
                spin: Scatter.adding(scatter.rotation, to: context.number(Param.spinFrom)),
                easing: TextExit.inEasing(named: context.choice(Param.easing)),
            )
        }
        var stream = rng.stream(TextExit.scatterTag)
        let spread = context.number(Param.outScatter)
        let turn = context.number(Param.outScatterRotation)
        let jitter = (x: stream.symmetric(spread), y: stream.symmetric(spread), rotation: stream.symmetric(turn))
        return TextExit.Target(
            dx: context.number(Param.outDrift) + jitter.x,
            dy: context.number(Param.outRise) + jitter.y,
            scale: context.number(Param.outScale),
            stretchX: outStretch.x,
            stretchY: outStretch.y,
            spin: context.number(Param.outSpin) + jitter.rotation,
            easing: TextExit.inEasing(named: context.choice(Param.outEasing)),
        )
    }

    /// The scale a glyph arrives from. Clamped only when jittered: a glyph
    /// cannot start inside out, and an unjittered start has to stay the very
    /// number it always was.
    private static func startScale(_ scaleFrom: Double, scatter: Scatter) -> Double {
        scatter.scale.map { max(0, scaleFrom + $0) } ?? scaleFrom
    }

    // ─── In Scatter ──────────────────────────────────────────────────────────

    /// One glyph's entrance jitter: `nil` on every axis whose amplitude is 0.
    ///
    /// All four are drawn whenever any is, in a fixed order, so turning one axis
    /// on never moves another's numbers. An axis at 0 contributes nothing at
    /// all rather than a drawn zero: `x + -0.0` is `x`, but the rule "an
    /// untouched axis is not in the arithmetic" is easier to keep than to
    /// reason about every time.
    private struct Scatter {
        var x: Double?
        var y: Double?
        var rotation: Double?
        var scale: Double?

        init(context: EffectContext, stream: EffectRandom) {
            let amplitudes = [
                context.number(Param.scatterX), context.number(Param.scatterY),
                context.number(Param.scatterRotation), context.number(Param.scatterScale),
            ]
            guard amplitudes.contains(where: { $0 != 0 }) else { return }
            var stream = stream
            let drawn = amplitudes.map { stream.symmetric($0) }
            func kept(_ index: Int) -> Double? { amplitudes[index] != 0 ? drawn[index] : nil }
            x = kept(0)
            y = kept(1)
            rotation = kept(2)
            scale = kept(3)
        }

        static func adding(_ jitter: Double?, to value: Double) -> Double {
            jitter.map { value + $0 } ?? value
        }
    }
}
