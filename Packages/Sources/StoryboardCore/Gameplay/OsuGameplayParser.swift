import Foundation

/// Reads `[Difficulty]`, `[TimingPoints]` and `[HitObjects]` from a `.osu`.
///
/// The file is somebody else's: every number is checked finite BEFORE any
/// integer conversion (`Int(.nan)` traps), clamped to a named bound, and a
/// line that cannot be read is skipped on its own without touching its
/// neighbours.
public enum OsuGameplayParser {
    public static let maxHitObjects = 20_000
    public static let maxControlPoints = 1_024
    public static let maxSlides = 512
    public static let maxPixelLength: Double = 100_000
    public static let coordinateLimit: Double = 10_000
    public static let timeLimit: Double = 1e7

    public static func parse(_ source: String) -> BeatmapGameplay {
        var section = ""
        var difficultyFields: [String: Double] = [:]
        var red: [UninheritedTimingPoint] = []
        var green: [InheritedPoint] = []
        var objects: [HitObject] = []
        var colours: [Int: ComboColour] = [:]
        var effectPoints: [(time: Double, kiai: Bool)] = []

        for rawLine in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmed()

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = line
                continue
            }
            if line.isEmpty || line.hasPrefix("//") { continue }

            switch section {
            case "[Difficulty]":
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = String(line[line.startIndex..<colon]).trimmed()
                // A non-finite value is the same as no value.
                if let value = Double(String(line[line.index(after: colon)...]).trimmed()), value.isFinite {
                    difficultyFields[key] = value
                }

            case "[TimingPoints]":
                parseControlPoint(line, red: &red, green: &green, effects: &effectPoints)

            case "[Colours]":
                parseColour(line, into: &colours)

            case "[HitObjects]":
                guard objects.count < maxHitObjects else { continue }
                if let object = parseHitObject(line) { objects.append(object) }

            default:
                continue
            }
        }

        return BeatmapGameplay(
            difficulty: difficulty(from: difficultyFields),
            controlPoints: ControlPoints(
                red: stableSorted(red) { $0.time < $1.time },
                green: stableSorted(green) { $0.time < $1.time },
            ),
            hitObjects: numbered(stableSorted(objects) { $0.time < $1.time }),
            comboColours: colours.isEmpty
                ? ComboColour.defaults
                : colours.sorted { $0.key < $1.key }.map(\.value),
            kiaiStarts: KiaiFountains.starts(from: effectPoints),
        )
    }

    // ─── Colours ─────────────────────────────────────────────────────────────

    /// `Combo3 : 120,193,232`. Other keys (SliderBorder, SliderTrackOverride...)
    /// are ignored: the border stays white.
    private static func parseColour(_ line: String, into colours: inout [Int: ComboColour]) {
        guard let colon = line.firstIndex(of: ":") else { return }
        let key = String(line[line.startIndex..<colon]).trimmed()
        guard key.hasPrefix("Combo"), let number = Int(key.dropFirst(5)),
              (1...ComboColour.maxCombos).contains(number)
        else { return }

        let channels = String(line[line.index(after: colon)...])
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmed() }
        // `r,g,b`, or `r,g,b,a` (the alpha is not used).
        guard channels.count == 3 || channels.count == 4 else { return }
        var bytes: [UInt8] = []
        for channel in channels.prefix(3) {
            // Finite BEFORE the conversion: UInt8(.nan) traps.
            guard let value = finite(channel) else { return }
            bytes.append(UInt8(min(max(value.rounded(), 0), 255)))
        }
        colours[number] = ComboColour(r: bytes[0], g: bytes[1], b: bytes[2])
    }

    // ─── Difficulty ──────────────────────────────────────────────────────────

    private static func difficulty(from fields: [String: Double]) -> BeatmapDifficulty {
        let base = BeatmapDifficulty.defaults
        func scale(_ key: String, fallback: Double) -> Double {
            fields[key].map { min(max($0, 0), 10) } ?? fallback
        }

        let od = scale("OverallDifficulty", fallback: base.od)
        return BeatmapDifficulty(
            hp: scale("HPDrainRate", fallback: base.hp),
            cs: scale("CircleSize", fallback: base.cs),
            od: od,
            // osu!: a map without ApproachRate uses its OverallDifficulty.
            ar: scale("ApproachRate", fallback: od),
            sliderMultiplier: fields["SliderMultiplier"].map {
                min(max($0, BeatmapDifficulty.sliderMultiplierRange.lowerBound), BeatmapDifficulty.sliderMultiplierRange.upperBound)
            } ?? base.sliderMultiplier,
            sliderTickRate: fields["SliderTickRate"].map {
                min(max($0, BeatmapDifficulty.sliderTickRateRange.lowerBound), BeatmapDifficulty.sliderTickRateRange.upperBound)
            } ?? base.sliderTickRate,
        )
    }

    // ─── Timing ──────────────────────────────────────────────────────────────

    private static func parseControlPoint(
        _ line: String,
        red: inout [UninheritedTimingPoint],
        green: inout [InheritedPoint],
        effects: inout [(time: Double, kiai: Bool)],
    ) {
        guard let point = TimingPointLine.parse(line) else { return }
        // Kiai rides on every timing point, red or green, valid tempo or not.
        if abs(point.time) <= timeLimit, effects.count < maxControlPoints {
            effects.append((time: point.time, kiai: point.kiai))
        }

        if point.isUninherited {
            // Same filter as OsuParser: a red point needs a real tempo.
            guard point.beatLength.isFinite, point.beatLength > 0 else { return }
            red.append(UninheritedTimingPoint(
                time: point.time,
                beatLength: point.beatLength,
                meter: point.meter == 0 ? 4 : point.meter,
                kiai: point.kiai,
            ))
        } else if let sv = ControlPoints.sv(forBeatLength: point.beatLength) {
            green.append(InheritedPoint(time: point.time, sv: sv))
        }
    }

    // ─── Hit objects ─────────────────────────────────────────────────────────

    private static let typeCircle = 1
    private static let typeSlider = 2
    private static let typeNewCombo = 4
    private static let typeSpinner = 8

    /// `x,y,time,type,hitSound,<object params>,<extras>`
    private static func parseHitObject(_ line: String) -> HitObject? {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmed() }
        guard parts.count >= 4,
              let x = finite(parts[0]), let y = finite(parts[1]), let rawTime = finite(parts[2]),
              let rawType = finite(parts[3])
        else { return nil }

        // Clamped before the Int conversion, so 1e308 cannot trap it.
        let type = Int(min(max(rawType, 0), 1_000_000))

        let position = PlayfieldPoint(x: clampCoordinate(x), y: clampCoordinate(y))
        let time = clampTime(rawTime)
        let newCombo = type & typeNewCombo != 0
        let comboSkip = (type >> 4) & 7

        func object(_ kind: HitObject.Kind) -> HitObject {
            HitObject(time: time, position: position, newCombo: newCombo, comboSkip: comboSkip, kind: kind)
        }

        if type & typeCircle != 0 {
            return object(.circle)
        }
        if type & typeSpinner != 0 {
            guard parts.count >= 6, let end = finite(parts[5]) else { return nil }
            return object(.spinner(endTime: max(clampTime(end), time)))
        }
        if type & typeSlider != 0 {
            guard parts.count >= 8,
                  let slider = parseSlider(curve: parts[5], slides: parts[6], length: parts[7])
            else { return nil }
            return object(.slider(slider))
        }
        // Anything else — mania hold notes (128) included — is not drawn.
        return nil
    }

    private static func parseSlider(curve: String, slides: String, length: String) -> HitObject.Slider? {
        let pieces = curve.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmed() }
        guard let letter = pieces.first, pieces.count > 1 else { return nil }

        let curveType: CurveType
        switch letter {
        case "L": curveType = .linear
        case "P": curveType = .perfect
        case "B": curveType = .bezier
        case "C": curveType = .catmull
        default: return nil
        }

        var points: [PlayfieldPoint] = []
        for piece in pieces.dropFirst() {
            // Points are `x:y` in the real format. (A comma would collide with
            // the field separator, so it cannot be an alternative spelling.)
            let parts = piece.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let x = finite(String(parts[0])), let y = finite(String(parts[1])) else {
                return nil
            }
            // Past the cap the extra points are dropped, not the slider.
            if points.count < maxControlPoints {
                points.append(PlayfieldPoint(x: clampCoordinate(x), y: clampCoordinate(y)))
            }
        }
        guard let slideCount = finite(slides), let pixelLength = finite(length) else { return nil }

        return HitObject.Slider(
            curve: curveType,
            points: points,
            slides: Int(min(max(slideCount, 1), Double(maxSlides))),
            pixelLength: min(max(pixelLength, 0), maxPixelLength),
        )
    }

    /// Combo numbers follow the time-sorted order, the one the player sees.
    ///
    /// The colour index follows osu!lazer's `OsuHitObject.UpdateComboInformation`:
    /// `index = last?.ComboIndexWithOffsets ?? 0`, and `index += ComboOffset + 1`
    /// when `this is not Spinner && (NewCombo || lastObj == null || lastObj is Spinner)`.
    /// Spinners never advance the colour even when flagged, and the skip bits
    /// only count on an object that carries the new-combo flag itself
    /// (`ConvertHitObjectParser`: `ComboOffset = newCombo ? comboOffset : 0`).
    private static func numbered(_ objects: [HitObject]) -> [HitObject] {
        var result = objects
        var number = 0
        var colourIndex = 0
        var forceNew = false
        for index in result.indices {
            let isSpinner: Bool
            if case .spinner = result[index].kind { isSpinner = true } else { isSpinner = false }
            let startsCombo = result[index].newCombo || forceNew || index == 0
            if startsCombo {
                number = 1
            } else {
                number += 1
            }
            if startsCombo, !isSpinner {
                colourIndex += (result[index].newCombo ? result[index].comboSkip : 0) + 1
            }
            result[index].comboIndexWithOffsets = colourIndex
            result[index].comboNumber = number
            // osu! starts a new combo on whatever follows a spinner.
            forceNew = isSpinner
        }
        return result
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private static func finite(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private static func clampCoordinate(_ value: Double) -> Double {
        min(max(value, -coordinateLimit), coordinateLimit)
    }

    private static func clampTime(_ value: Double) -> Double {
        min(max(value, -timeLimit), timeLimit)
    }

    /// `sort` is not documented as stable, and equal-time objects must keep
    /// file order: the index is the tie-break.
    private static func stableSorted<T>(_ items: [T], by before: (T, T) -> Bool) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                before(lhs.element, rhs.element) || (!before(rhs.element, lhs.element) && lhs.offset < rhs.offset)
            }
            .map(\.element)
    }
}
