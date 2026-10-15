import Foundation

/// Parses `.osb` files (and the `[Events]` section of `.osu` files) into a
/// ``Storyboard``.
///
/// Ported from `app/lib/parser/osb.ts`.
public enum OsbParser {
    public static func parse(_ source: String) -> Storyboard {
        var sprites: [StoryboardSprite] = []
        var samples: [StoryboardSample] = []
        var variables: [String: String] = [:]

        var section = ""
        var spriteIndex = 0
        var currentLoop: LoopGroup?

        /// Pushes a finished loop onto the sprite currently being built.
        func commitLoop() {
            guard let loop = currentLoop, !loop.commands.isEmpty,
                  !sprites.isEmpty
            else {
                currentLoop = nil
                return
            }
            sprites[sprites.count - 1].loops.append(loop)
            currentLoop = nil
        }

        // Splitting on "\n" leaves a trailing "\r" on CRLF files, which would
        // otherwise become part of section headers such as "[Events]\r".
        for rawLine in source.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline,
        ) {
            let line = rawLine.trimmingTrailingWhitespace()

            // ── Section headers ──
            if line.hasPrefix("[") {
                commitLoop()
                section = line
                continue
            }

            // ── Variables ──
            if section == "[Variables]" {
                if let eq = line.firstIndex(of: "=") {
                    let key = String(line[line.startIndex..<eq]).trimmed()
                    let value = String(line[line.index(after: eq)...]).trimmed()
                    variables[key] = value
                }
                continue
            }

            guard section == "[Events]" else { continue }
            if line.isEmpty || line.hasPrefix("//") { continue }

            let depth = indentDepth(of: line)

            if depth == 0 {
                // A sample is not a sprite: it neither starts one nor ends the
                // one before it, so the sprites around it keep their commands.
                if line.hasPrefix("Sample") {
                    commitLoop()
                    if let sample = parseSampleLine(line) { samples.append(sample) }
                    continue
                }
                // New sprite — commit any open loop first.
                commitLoop()
                if let sprite = parseSpriteLine(line, index: spriteIndex) {
                    spriteIndex += 1
                    sprites.append(sprite)
                }
                continue
            }

            guard !sprites.isEmpty else { continue }

            let trimmed = line.trimmed()
            let clean = trimmed.strippingLeadingUnderscores()
            let type = clean.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map { $0.trimmed() } ?? ""

            if depth == 1, type == "L" {
                // Loop header — commit the previous loop and start a new one.
                commitLoop()
                let parts = clean.split(separator: ",", omittingEmptySubsequences: false)
                currentLoop = LoopGroup(
                    startTime: parts.count > 1 ? (Double(parts[1].trimmed()) ?? 0) : 0,
                    loopCount: max(1, parts.count > 2 ? (Int(parts[2].trimmed()) ?? 1) : 1),
                )
            } else if depth >= 2, currentLoop != nil {
                // Command inside a loop body — times are relative to the iteration.
                if let command = parseCommandLine(trimmed) {
                    currentLoop?.commands.append(command)
                }
            } else {
                // Direct command — commit any open loop first.
                commitLoop()
                if let command = parseCommandLine(trimmed) {
                    sprites[sprites.count - 1].commands.append(command)
                }
            }
        }

        // Commit a loop still open at EOF.
        commitLoop()

        return Storyboard(sprites: sprites, variables: variables, samples: samples)
    }

    // ─── Sprite parsing ──────────────────────────────────────────────────────

    /// Parses a `Sprite,...` or `Animation,...` header line.
    ///
    /// An `Animation` whose header osu! has no defaults for (missing or
    /// non-positive count or delay, a count over the cap) is kept as a static
    /// sprite showing its base file.
    static func parseSpriteLine(_ line: String, index: Int) -> StoryboardSprite? {
        let parts = splitCsvRespectingQuotes(line)
        guard let type = parts.first?.trimmed(),
              type == "Sprite" || type == "Animation"
        else { return nil }

        let layer = Layer(osbName: parts.count > 1 ? parts[1].trimmed() : "")
        let origin = Origin(osbName: parts.count > 2 ? parts[2].trimmed() : "")
        let filePath = (parts.count > 3 ? parts[3] : "").trimmed().strippingSurroundingQuotes()

        // Only a missing or unreadable field falls back. The TypeScript source
        // used `parseFloat(...) || 320`, where 0 is falsy, so a letterbox bar
        // at y = 0 was hung from the middle of the screen.
        let x = finiteDouble(parts, 4) ?? 320
        let y = finiteDouble(parts, 5) ?? 240

        return StoryboardSprite(
            id: "sprite_\(index)",
            layer: layer,
            origin: origin,
            filePath: filePath,
            defaultX: x,
            defaultY: y,
            animation: type == "Animation" ? animationHeader(parts) : nil,
        )
    }

    /// Fields 6 to 8 of an `Animation` line, or `nil` when they cannot drive one.
    private static func animationHeader(_ parts: [String]) -> SpriteAnimation? {
        // Read as Double and checked before converting: `Int(1e30)` traps.
        guard let count = finiteDouble(parts, 6), count >= 1,
              count <= Double(AnimationFrames.maximumFrameCount),
              let delay = finiteDouble(parts, 7), delay > 0
        else { return nil }

        let loop = AnimationLoopType(osbName: parts.count > 8 ? parts[8].trimmed() : "")
        return SpriteAnimation(frameCount: Int(count), frameDelay: delay, loopType: loop)
    }

    /// Parses `Sample,<time>,<layer>,"<path>",<volume>`.
    ///
    /// `nil` for a line that cannot be a sample (no time, no path), so one bad
    /// line costs itself and not the rest of the file.
    static func parseSampleLine(_ line: String) -> StoryboardSample? {
        let parts = splitCsvRespectingQuotes(line)
        guard parts.first?.trimmed() == "Sample",
              let time = doubleField(parts, 1), time.isFinite, abs(time) < 1e15
        else { return nil }

        let path = (parts.count > 3 ? parts[3] : "").trimmed().strippingSurroundingQuotes()
        guard !path.isEmpty else { return nil }

        // A numeric layer is an index into the four the format has; anything
        // else — Overlay, 4, a typo — is Foreground rather than a dropped sound.
        let layerField = parts.count > 2 ? parts[2].trimmed() : ""
        let layer: Layer
        if let index = Int(layerField) {
            let order: [Layer] = [.background, .fail, .pass, .foreground]
            layer = order.indices.contains(index) ? order[index] : .foreground
        } else {
            layer = Layer(osbName: layerField) == .overlay ? .foreground : Layer(osbName: layerField)
        }

        // Blank or absent means full volume, which is what osu! plays.
        let volume = intField(parts, 4) ?? 100
        return StoryboardSample(
            time: time.rounded(),
            layer: layer,
            path: path,
            volume: min(100, max(0, volume)),
        )
    }

    // ─── Command parsing ─────────────────────────────────────────────────────

    /// Parses a single command line.
    ///
    /// Returns `nil` for `L` (loop headers, handled by the caller) and `T`
    /// (triggers, not supported yet — see the note in ``parse(_:)``).
    static func parseCommandLine(_ line: String) -> Command? {
        let clean = line.strippingLeadingUnderscores()
        let parts = clean.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let type = parts.first?.trimmed() else { return nil }

        let easing = Easing(rawValueOrLinear: intField(parts, 1) ?? 0)
        let startTime = Double(intField(parts, 2) ?? 0)
        // A blank endTime means an instant command: endTime == startTime.
        let endTime = blankAware(parts, 3).flatMap { Double($0) }.map { Double(Int($0)) } ?? startTime

        let timing = Command.Timing(easing: easing, startTime: startTime, endTime: endTime)

        /// Reads field `index`, falling back to `fallback` when blank or absent.
        func value(_ index: Int, or fallback: Double) -> Double {
            doubleField(parts, index) ?? fallback
        }

        switch type {
        case "F":
            let start = value(4, or: 0)
            return Command(timing: timing, payload: .fade(start: start, end: value(5, or: start)))

        case "M":
            let startX = value(4, or: 0)
            let startY = value(5, or: 0)
            return Command(timing: timing, payload: .move(
                startX: startX, startY: startY,
                endX: value(6, or: startX), endY: value(7, or: startY),
            ))

        case "MX":
            let start = value(4, or: 0)
            return Command(timing: timing, payload: .moveX(start: start, end: value(5, or: start)))

        case "MY":
            let start = value(4, or: 0)
            return Command(timing: timing, payload: .moveY(start: start, end: value(5, or: start)))

        case "S":
            let start = value(4, or: 1)
            return Command(timing: timing, payload: .scale(start: start, end: value(5, or: start)))

        case "V":
            let startX = value(4, or: 1)
            let startY = value(5, or: 1)
            return Command(timing: timing, payload: .vectorScale(
                startX: startX, startY: startY,
                endX: value(6, or: startX), endY: value(7, or: startY),
            ))

        case "R":
            let start = value(4, or: 0)
            return Command(timing: timing, payload: .rotate(start: start, end: value(5, or: start)))

        case "C":
            let startR = value(4, or: 255)
            let startG = value(5, or: 255)
            let startB = value(6, or: 255)
            return Command(timing: timing, payload: .color(
                startR: startR, startG: startG, startB: startB,
                endR: value(7, or: startR),
                endG: value(8, or: startG),
                endB: value(9, or: startB),
            ))

        case "P":
            let raw = parts.count > 4 ? parts[4].trimmed() : "H"
            return Command(
                timing: timing,
                payload: .parameter(ParameterKind(rawValue: raw) ?? .flipHorizontal),
            )

        // `L` is handled by the caller; `T` (triggers) is not supported yet.
        default:
            return nil
        }
    }

    // ─── Field helpers ───────────────────────────────────────────────────────

    /// Returns the trimmed field at `index`, or `nil` when absent or blank.
    private static func blankAware(_ parts: [String], _ index: Int) -> String? {
        guard index < parts.count else { return nil }
        let value = parts[index].trimmed()
        return value.isEmpty ? nil : value
    }

    private static func intField(_ parts: [String], _ index: Int) -> Int? {
        blankAware(parts, index).flatMap { Int($0) ?? Double($0).map { Int($0) } }
    }

    private static func doubleField(_ parts: [String], _ index: Int) -> Double? {
        blankAware(parts, index).flatMap(Double.init)
    }

    private static func finiteDouble(_ parts: [String], _ index: Int) -> Double? {
        guard let value = doubleField(parts, index), value.isFinite else { return nil }
        return value
    }

    // ─── Line helpers ────────────────────────────────────────────────────────

    /// Counts leading underscores and spaces to determine nesting depth.
    static func indentDepth(of line: String) -> Int {
        var depth = 0
        for character in line {
            guard character == "_" || character == " " else { break }
            depth += 1
        }
        return depth
    }

    /// Splits a CSV line, treating commas inside double quotes as literal.
    ///
    /// e.g. `Sprite,Foreground,Centre,"sb/logo.png",320,240`
    static func splitCsvRespectingQuotes(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuote = false

        for character in line {
            switch character {
            case "\"":
                inQuote.toggle()
                current.append(character)
            case "," where !inQuote:
                result.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        result.append(current)
        return result
    }
}

// ─── String conveniences ─────────────────────────────────────────────────────

extension StringProtocol {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespaces)
    }

    func trimmingTrailingWhitespace() -> String {
        var value = String(self)
        while let last = value.last, last == " " || last == "\t" || last == "\r" {
            value.removeLast()
        }
        return value
    }

    func strippingLeadingUnderscores() -> String {
        String(drop(while: { $0 == "_" }))
    }

    func strippingSurroundingQuotes() -> String {
        var value = String(self)
        if value.hasPrefix("\"") { value.removeFirst() }
        if value.hasSuffix("\"") { value.removeLast() }
        return value
    }
}
