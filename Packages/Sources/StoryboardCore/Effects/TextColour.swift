import Foundation

/// What colour each glyph is tinted, and when it changes.
///
/// Pure like `TextExit`. The glyph texture is white and the colour arrives as
/// `_C`, so one image serves every colour — and every mode here costs at most
/// three `_C` per glyph: the format writes one line per command, per glyph.
///
/// A Tint filter on the track replaces every `_C` a glyph carries, these
/// included: Tint wins. That is the filter's job, and a mode that fought it
/// would leave two controls each half in charge of one colour.
enum TextColour {
    /// The stream a Random sweep shuffles from, derived from the effect's own,
    /// so choosing a sweep order never moves the entrance's Random shuffle.
    static let orderTag = 0xC010

    enum Mode: String, CaseIterable {
        case solid = "Solid", gradient = "Gradient", highlight = "Highlight"
    }

    static let parameters: [EffectParameter] = {
        typealias P = TextEffect.Param
        let second = ["Gradient", "Highlight"]
        let highlight = EffectParameter.Condition(parameter: P.colourMode, isAnyOf: ["Highlight"])
        return [
            EffectParameter(
                id: P.color, name: "Colour", group: "Colour",
                defaultValue: .color(EffectColor(r: 255, g: 255, b: 255)),
            ),
            EffectParameter(
                id: P.additive, name: "Additive", group: "Colour",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: P.colourMode, name: "Colour Mode", group: "Colour",
                defaultValue: .choice(Mode.solid.rawValue), options: Mode.allCases.map(\.rawValue),
            ),
            EffectParameter(
                id: P.colour2, name: "Second Colour", group: "Colour",
                defaultValue: .color(EffectColor(r: 255, g: 214, b: 64)),
                shownWhen: .init(parameter: P.colourMode, isAnyOf: second),
            ),
            EffectParameter(
                id: P.gradientAcross, name: "Across", group: "Colour",
                defaultValue: .choice("Line"), options: ["Line", "Block"],
                shownWhen: .init(parameter: P.colourMode, isAnyOf: ["Gradient"]),
            ),
            EffectParameter(
                id: P.sweepOrder, name: "Sweep Order", group: "Colour",
                defaultValue: .choice("Start"), options: ["Start", "End", "Centre", "Edges", "Random"],
                shownWhen: highlight,
            ),
            // When the sweep starts and how much of the clip it takes, as
            // shares of the clip: the same sweep on a longer clip runs slower
            // rather than finishing early.
            EffectParameter(
                id: P.sweepStart, name: "Sweep Start", group: "Colour",
                defaultValue: .number(0), range: 0...100, step: 1, unit: "%",
                shownWhen: highlight,
            ),
            EffectParameter(
                id: P.sweepLength, name: "Sweep Length", group: "Colour",
                defaultValue: .number(60), range: 0...100, step: 1, unit: "%",
                shownWhen: highlight,
            ),
            EffectParameter(
                id: P.sweepEdge, name: "Edge", group: "Colour",
                defaultValue: .number(120), range: 0...2000, step: 10, unit: "ms",
                shownWhen: highlight,
            ),
            EffectParameter(
                id: P.flash, name: "Flash", group: "Colour",
                defaultValue: .toggle(false),
                shownWhen: highlight,
            ),
        ]
    }()

    /// Each glyph's base colour and, under Highlight, when its sweep reaches
    /// it. `glyphs` are each glyph's x and line, in reading order.
    static func plan(
        _ glyphs: [(x: Double, line: Int)],
        units: [Int],
        sung: [Double]? = nil,
        context: EffectContext,
        rng: EffectRandom,
    ) -> [(colour: EffectColor, highlightAt: Double?)] {
        typealias P = TextEffect.Param
        let base = context.color(P.color)
        switch Mode(rawValue: context.choice(P.colourMode)) ?? .solid {
        case .solid:
            return glyphs.map { _ in (base, nil) }
        case .gradient:
            let block = context.choice(P.gradientAcross) == "Block"
            return gradient(
                xs: glyphs.map(\.x), groups: glyphs.map { block ? 0 : $0.line },
                from: base, to: context.color(P.colour2),
            ).map { ($0, nil) }
        case .highlight:
            let order = context.choice(P.sweepOrder)
            // Each word lit at the moment it was sung — what makes this karaoke
            // rather than a sweep. Without timing, `Sung` sweeps from the start.
            if order == SungTiming.choice, let sung {
                return sung.map { (base, $0) }
            }
            // From its own stream: a Random sweep never moves the entrance's
            // Random shuffle, which draws from the effect's stream itself.
            var stream = rng.stream(orderTag)
            let ranks = TextStagger.ranks(
                units: units, order: order == SungTiming.choice ? "Start" : order, waveAmount: 0, rng: &stream,
            )
            return highlightTimes(
                ranks: ranks, start: context.number(P.sweepStart),
                length: context.number(P.sweepLength), duration: context.duration,
            ).map { (base, $0) }
        }
    }

    /// Each glyph's colour along a gradient from `from` to `to`, by its place
    /// across its group (a line, or the whole block). A group of one glyph
    /// takes `from`.
    static func gradient(xs: [Double], groups: [Int], from: EffectColor, to: EffectColor) -> [EffectColor] {
        var bounds: [Int: (low: Double, high: Double)] = [:]
        for (x, group) in zip(xs, groups) {
            let known = bounds[group] ?? (x, x)
            bounds[group] = (min(known.low, x), max(known.high, x))
        }
        return zip(xs, groups).map { x, group in
            guard let range = bounds[group], range.high > range.low else { return from }
            return mix(from, to, (x - range.low) / (range.high - range.low))
        }
    }

    /// When each glyph's highlight starts, in clip time: its share of the
    /// sweep by rank, so the last ranked glyph lands at `start + length`.
    static func highlightTimes(ranks: [Double], start: Double, length: Double, duration: Double) -> [Double] {
        let top = ranks.max() ?? 0
        return ranks.map { rank in
            duration * (start + (top > 0 ? rank / top * length : 0)) / 100
        }
    }

    /// One glyph's `_C` commands.
    ///
    /// A highlight replaces the base `_C` rather than following it: before its
    /// first command a sprite holds that command's start colour, which is the
    /// base — a separate one restating it would be a line for nothing. A
    /// highlight due after the glyph is gone writes the base alone, and white
    /// writes nothing at all.
    static func commands(
        base: EffectColor,
        highlight: (colour: EffectColor, at: Double)?,
        edge: Double,
        flash: Bool,
        birth: Double,
        life: Double,
    ) -> [Command] {
        guard let highlight, max(birth, highlight.at) < life else {
            return base == .white ? [] : [tint(base, base, birth, birth)]
        }
        let start = max(birth, highlight.at)
        let lit = min(start + edge, life)
        var commands = [tint(base, highlight.colour, start, lit)]
        if flash, lit < life {
            commands.append(tint(highlight.colour, base, lit, min(lit + edge, life)))
        }
        return commands
    }

    private static func tint(_ from: EffectColor, _ to: EffectColor, _ start: Double, _ end: Double) -> Command {
        Command(
            easing: .linear, startTime: start, endTime: end,
            payload: .color(startR: from.r, startG: from.g, startB: from.b, endR: to.r, endG: to.g, endB: to.b),
        )
    }

    /// Rounded per channel: the format writes colour as whole numbers.
    private static func mix(_ a: EffectColor, _ b: EffectColor, _ share: Double) -> EffectColor {
        func channel(_ x: Double, _ y: Double) -> Double { (x + (y - x) * share).rounded() }
        return EffectColor(r: channel(a.r, b.r), g: channel(a.g, b.g), b: channel(a.b, b.b))
    }
}
