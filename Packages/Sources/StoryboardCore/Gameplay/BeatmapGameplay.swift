import Foundation

/// A point in osu!'s 512x384 playfield, before it is mapped onto the canvas.
public struct PlayfieldPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The `[Difficulty]` numbers the overlay needs.
public struct BeatmapDifficulty: Sendable, Equatable {
    public var hp: Double
    public var cs: Double
    public var od: Double
    public var ar: Double
    public var sliderMultiplier: Double
    public var sliderTickRate: Double

    public static let sliderMultiplierRange: ClosedRange<Double> = 0.4...3.6
    public static let sliderTickRateRange: ClosedRange<Double> = 0.1...8
    /// What a file with no `[Difficulty]` section means: osu!'s own defaults.
    public static let defaults = BeatmapDifficulty(
        hp: 5, cs: 5, od: 5, ar: 5, sliderMultiplier: 1.4, sliderTickRate: 1,
    )

    public init(
        hp: Double = 5,
        cs: Double = 5,
        od: Double = 5,
        ar: Double = 5,
        sliderMultiplier: Double = 1.4,
        sliderTickRate: Double = 1,
    ) {
        self.hp = hp
        self.cs = cs
        self.od = od
        self.ar = ar
        self.sliderMultiplier = sliderMultiplier
        self.sliderTickRate = sliderTickRate
    }
}

public enum CurveType: Sendable, Equatable {
    case linear
    case perfect
    case bezier
    case catmull
}

public struct HitObject: Sendable, Equatable {
    public struct Slider: Sendable, Equatable {
        public var curve: CurveType
        /// The control points AFTER the head: the head is the object's own
        /// position, so it is not repeated here.
        public var points: [PlayfieldPoint]
        public var slides: Int
        public var pixelLength: Double

        public init(curve: CurveType, points: [PlayfieldPoint], slides: Int, pixelLength: Double) {
            self.curve = curve
            self.points = points
            self.slides = slides
            self.pixelLength = pixelLength
        }
    }

    public enum Kind: Sendable, Equatable {
        case circle
        case slider(Slider)
        case spinner(endTime: Double)
    }

    public var time: Double
    public var position: PlayfieldPoint
    public var newCombo: Bool
    /// Colour-skip bits (4-6 of the type field). They pick a colour, not a
    /// number, so they never touch ``comboNumber``.
    public var comboSkip: Int
    /// 1-based index inside the combo, the number osu! draws on the circle.
    public var comboNumber: Int
    /// `ComboIndexWithOffsets` of osu!lazer's `IHasComboInformation`: 1 for the
    /// first object, then `+ comboSkip + 1` on every new combo. The palette is
    /// indexed with it (see ``ComboColour/pick(from:indexWithOffsets:)``).
    public var comboIndexWithOffsets: Int
    public var kind: Kind

    public init(
        time: Double,
        position: PlayfieldPoint,
        newCombo: Bool = false,
        comboSkip: Int = 0,
        comboNumber: Int = 1,
        comboIndexWithOffsets: Int = 1,
        kind: Kind,
    ) {
        self.time = time
        self.position = position
        self.newCombo = newCombo
        self.comboSkip = comboSkip
        self.comboNumber = comboNumber
        self.comboIndexWithOffsets = comboIndexWithOffsets
        self.kind = kind
    }
}

/// A combo colour as the `.osu` writes it: 0-255 channels, used as-is (the
/// overlay composes in gamma space, like the rest of the renderer).
public struct ComboColour: Sendable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// osu!'s `SkinConfiguration.DefaultComboColours`, used when the map has no
    /// `[Colours]` combo entry (checked against ppy/osu master).
    public static let defaults: [ComboColour] = [
        ComboColour(r: 255, g: 192, b: 0),
        ComboColour(r: 0, g: 202, b: 0),
        ComboColour(r: 18, g: 124, b: 255),
        ComboColour(r: 242, g: 24, b: 57),
    ]

    /// Combo1 ... Combo8 is the most osu! reads.
    public static let maxCombos = 8

    /// The colour of an object. osu!lazer's `LegacyBeatmapSkin.GetComboColour`
    /// passes `ComboIndexWithOffsets` to `LegacySkin.GetComboColour`, which reads
    /// `ComboColours[colourIndex % count]`. The `(index + count - 1) % count` in
    /// lazer's editor belongs to its new-combo button, not to gameplay: using it
    /// put every colour one step early against a capture of the game. An empty
    /// palette falls back to the defaults.
    public static func pick(from palette: [ComboColour], indexWithOffsets: Int) -> ComboColour {
        let colours = palette.isEmpty ? defaults : palette
        let count = colours.count
        // `Int.min` and friends cannot occur from the parser, but a hand-made
        // object could carry them: a floor-mod never indexes out of range.
        let position = ((indexWithOffsets % count) + count) % count
        return colours[position]
    }
}

/// Everything a gameplay overlay reads from one `.osu`.
///
/// Parsed apart from ``BeatmapTimingData``: opening a project must not pay for
/// hit objects, and the existing model (and its golden tests) stays untouched.
public struct BeatmapGameplay: Sendable, Equatable {
    public var difficulty: BeatmapDifficulty
    public var controlPoints: ControlPoints
    public var hitObjects: [HitObject]
    /// `[Colours]` Combo1...8 in order; the osu! defaults when the map has none.
    public var comboColours: [ComboColour]

    public init(
        difficulty: BeatmapDifficulty,
        controlPoints: ControlPoints,
        hitObjects: [HitObject],
        comboColours: [ComboColour] = ComboColour.defaults,
    ) {
        self.difficulty = difficulty
        self.controlPoints = controlPoints
        self.hitObjects = hitObjects
        self.comboColours = comboColours
    }

    public func comboColour(for object: HitObject) -> ComboColour {
        ComboColour.pick(from: comboColours, indexWithOffsets: object.comboIndexWithOffsets)
    }
}
