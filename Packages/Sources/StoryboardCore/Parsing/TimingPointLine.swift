import Foundation

/// One `[TimingPoints]` line, read the same way by every consumer.
///
/// ``OsuParser`` (red points, kiai) and ``OsuGameplayParser`` (red + green)
/// both read this section. Two copies of the field layout would let "which
/// flag means inherited" drift between them, so the line is parsed once.
struct TimingPointLine: Equatable {
    var time: Double
    /// Milliseconds per beat when red; a negative slider-velocity code when green.
    var beatLength: Double
    var meter: Int
    var isUninherited: Bool
    var kiai: Bool

    /// `time,beatLength,meter,sampleSet,sampleIndex,volume,uninherited,effects`
    static func parse(_ line: String) -> TimingPointLine? {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmed() }
        guard parts.count >= 2 else { return nil }

        // A non-numeric field falls to 0 as it always has, but a NaN/inf time
        // is rejected: it would poison every sort and every `Int(...)` after.
        let time = (Double(parts[0]) ?? 0).rounded()
        guard time.isFinite else { return nil }
        let beatLength = Double(parts[1]) ?? 0
        let meter = parts.count > 2 ? (Int(parts[2]) ?? 4) : 4
        // The uninherited flag defaults to 1 when absent, matching older files.
        let isUninherited = parts.count > 6 ? (Int(parts[6]) ?? 1) == 1 : true
        let effects = parts.count > 7 ? (Int(parts[7]) ?? 0) : 0

        return TimingPointLine(
            time: time,
            beatLength: beatLength,
            meter: meter,
            isUninherited: isUninherited,
            kiai: effects & 1 == 1,
        )
    }
}
