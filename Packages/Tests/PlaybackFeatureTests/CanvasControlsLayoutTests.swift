import Testing
@testable import PlaybackFeature

/// The control bar is one row of fixed-height pills: a label that grows with
/// its content squeezes everything beside it, and the timecode was what gave
/// way, wrapping onto two lines (reported once the difficulty menu appeared).
@Suite("Canvas controls layout")
struct CanvasControlsLayoutTests {
    @Test("a short difficulty name is shown whole")
    func shortNameUntouched() {
        #expect(GameplayOverlayControls.shortName("Insane") == "Insane")
        #expect(GameplayOverlayControls.shortName("8 (timing)") == "8 (timing)")
    }

    @Test("a long difficulty name is cut to a bounded label with an ellipsis")
    func longNameTruncated() {
        let long = "Kalindraz's Ultra Extreme Insane"
        let shown = GameplayOverlayControls.shortName(long)

        #expect(shown.count == GameplayOverlayControls.nameLimit)
        #expect(shown.hasSuffix("…"))
        #expect(long.hasPrefix(String(shown.dropLast())))
    }

    @Test("the timing marker survives truncation: it says why this one is the default")
    func timingMarkerKept() {
        let shown = GameplayOverlayControls.shortName("Kalindraz's Ultra Extreme Insane (timing)")

        #expect(shown.hasSuffix("… (timing)"))
        #expect(shown.hasPrefix("Kalindraz"))
        #expect(shown.count == GameplayOverlayControls.nameLimit + " (timing)".count)
    }
}
