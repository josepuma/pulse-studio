import Foundation

/// Writes sprites back out as storyboard text.
///
/// The inverse of `OsbParser`, and deliberately close enough to it that the two
/// can be tested against each other: anything this writes, that reads.
public enum OsbWriter {
    /// The whole file, sprites grouped under their layer headings.
    public static func write(_ sprites: [StoryboardSprite], samples: [StoryboardSample] = []) -> String {
        var lines = ["[Events]", "//Background and Video events"]

        // Grouped by layer because the format says so, and in the order the
        // layers draw. Within a layer the array order is kept: it is the draw
        // order everywhere else in the app, and sorting here would quietly
        // disagree with what the canvas showed.
        for layer in Layer.allCases.sorted(by: { $0.renderOrder < $1.renderOrder }) {
            lines.append("//Storyboard Layer \(layer.renderOrder) (\(layer.rawValue))")
            for sprite in sprites where sprite.layer == layer {
                lines.append(contentsOf: self.lines(for: sprite))
            }
        }

        lines.append("//Storyboard Sound Samples")
        lines.append(contentsOf: sampleLines(samples))
        return lines.joined(separator: "\n") + "\n"
    }

    // ─── Samples ─────────────────────────────────────────────────────────────

    /// One line per sample, in time order.
    ///
    /// Sorted here because the format reads them as a list and a hand-built
    /// array is in whatever order it was made; ties keep their given order
    /// (the index is the tiebreak, so this does not lean on the sort being
    /// stable). A path with a quote is left out for the reason a sprite's is:
    /// it would end the field early and corrupt the line.
    private static func sampleLines(_ samples: [StoryboardSample]) -> [String] {
        samples.enumerated()
            .filter { !$0.element.path.isEmpty && !$0.element.path.contains("\"") }
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map { _, sample in
                // The format has four layers: Overlay has no number to give.
                let layer = min(3, sample.layer.renderOrder)
                let volume = min(100, max(0, sample.volume))
                return "Sample,\(time(sample.time)),\(layer),\"\(sample.path)\",\(volume)"
            }
    }

    // ─── One sprite ──────────────────────────────────────────────────────────

    private static func lines(for sprite: StoryboardSprite) -> [String] {
        // The shared head; an animated sprite only changes the keyword and
        // appends its frame fields.
        let head = "\(sprite.layer.rawValue),\(sprite.origin.rawValue),"
            + "\"\(sprite.filePath)\",\(number(sprite.defaultX)),\(number(sprite.defaultY))"
        var lines: [String]
        if let animation = sprite.animation {
            // The loop type is always spelled out: a header that arrived with it
            // missing or misspelled reads as LoopForever, and the file should
            // say so rather than depend on every reader guessing the same.
            lines = [
                "Animation,\(head),\(animation.frameCount),\(number(animation.frameDelay)),"
                    + animation.loopType.rawValue,
            ]
        } else {
            lines = ["Sprite,\(head)"]
        }

        for command in sprite.commands {
            lines.append(" " + line(for: command))
        }

        // A loop's body is indented one level deeper, and its times are
        // relative to each iteration rather than to the file.
        for loop in sprite.loops {
            lines.append(" L,\(time(loop.startTime)),\(loop.loopCount)")
            for command in loop.commands {
                lines.append("  " + line(for: command))
            }
        }

        return lines
    }

    private static func line(for command: Command) -> String {
        let timing = command.timing
        // An end time equal to the start is written blank, which is how the
        // format spells "hold this value" — and how the parser reads it back.
        let end = timing.endTime == timing.startTime ? "" : time(timing.endTime)
        let head = "\(command.kind.rawValue),\(timing.easing.rawValue)"
            + ",\(time(timing.startTime)),\(end)"

        switch command.payload {
        case let .fade(start, end):
            return head + ",\(number(start)),\(number(end))"
        case let .move(startX, startY, endX, endY):
            return head + ",\(number(startX)),\(number(startY)),\(number(endX)),\(number(endY))"
        case let .moveX(start, end):
            return head + ",\(number(start)),\(number(end))"
        case let .moveY(start, end):
            return head + ",\(number(start)),\(number(end))"
        case let .scale(start, end):
            return head + ",\(number(start)),\(number(end))"
        case let .vectorScale(startX, startY, endX, endY):
            return head + ",\(number(startX)),\(number(startY)),\(number(endX)),\(number(endY))"
        case let .rotate(start, end):
            // Radians on both sides, so no conversion.
            return head + ",\(number(start)),\(number(end))"
        case let .color(startR, startG, startB, endR, endG, endB):
            return head
                + ",\(channel(startR)),\(channel(startG)),\(channel(startB))"
                + ",\(channel(endR)),\(channel(endG)),\(channel(endB))"
        case let .parameter(kind):
            return head + ",\(kind.rawValue)"
        }
    }

    // ─── Numbers ─────────────────────────────────────────────────────────────

    /// Trims a value to what the format needs.
    ///
    /// Whole numbers lose their decimal point and the rest keep at most three
    /// places. A storyboard is text, and one sprite can carry thousands of
    /// numbers: writing `320.0` rather than `320`, or seventeen digits of a
    /// float's exact value, costs real megabytes over a whole file for
    /// precision far below a pixel.
    private static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 1000).rounded() / 1000
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            return String(Int(rounded))
        }
        return String(format: "%.3f", rounded)
    }

    /// A time, which the format takes as a WHOLE NUMBER of milliseconds.
    ///
    /// osu! rejects a storyboard whose command times carry a decimal point —
    /// not by drawing it oddly, by refusing the file. And times arrive here
    /// fractional all the time: an effect divides its clip into segments, a
    /// beat at 169.4 BPM is 354.19ms, and a script is free to put a command
    /// anywhere it likes.
    ///
    /// Rounded rather than truncated, so a command lands on the nearer
    /// millisecond instead of always the earlier one — a systematic half-ms
    /// bias upstream of a thousand commands is drift, where rounding cancels.
    private static func time(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        // Clamped to what an `Int` can hold, because a NaN guarded above still
        // leaves an infinity-sized double able to trap on conversion.
        let rounded = value.rounded()
        guard abs(rounded) < 1e15 else { return "0" }
        return String(Int(rounded))
    }

    /// Colour channels are whole numbers in [0, 255].
    private static func channel(_ value: Double) -> String {
        String(min(255, max(0, Int(value.rounded()))))
    }
}
