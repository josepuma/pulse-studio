import Testing

@testable import StoryboardCore

@Suite("Gameplay difficulty parsing")
struct DifficultyTests {
    private func difficulty(_ body: String) -> BeatmapDifficulty {
        OsuGameplayParser.parse("[Difficulty]\n\(body)").difficulty
    }

    @Test("reads the exact values (S1.1a)")
    func exactValues() {
        let d = difficulty("""
        HPDrainRate:3
        CircleSize:4
        OverallDifficulty:8
        ApproachRate:9
        SliderMultiplier:1.8
        SliderTickRate:2
        """)

        #expect(d.hp == 3)
        #expect(d.cs == 4)
        #expect(d.od == 8)
        #expect(d.ar == 9)
        #expect(d.sliderMultiplier == 1.8)
        #expect(d.sliderTickRate == 2)
    }

    @Test("a missing ApproachRate follows OverallDifficulty (S1.1b)")
    func approachRateFallsBackToOD() {
        #expect(difficulty("OverallDifficulty:7").ar == 7)
        // Present wins over the fallback, even when it is lower.
        #expect(difficulty("OverallDifficulty:7\nApproachRate:3").ar == 3)
    }

    @Test("non-finite values use the default and never trap (S1.1c)")
    func nonFinite() {
        let d = difficulty("""
        CircleSize:NaN
        ApproachRate:inf
        SliderMultiplier:-inf
        OverallDifficulty:nan
        """)

        #expect(d.cs == BeatmapDifficulty.defaults.cs)
        #expect(d.ar == BeatmapDifficulty.defaults.ar)
        #expect(d.sliderMultiplier == BeatmapDifficulty.defaults.sliderMultiplier)
    }

    @Test("no [Difficulty] section gives the defaults (S1.1d)")
    func noSection() {
        let d = OsuGameplayParser.parse("[General]\nAudioFilename: a.mp3").difficulty

        #expect(d == BeatmapDifficulty.defaults)
        #expect(d.hp == 5 && d.cs == 5 && d.od == 5 && d.ar == 5)
        #expect(d.sliderMultiplier == 1.4 && d.sliderTickRate == 1)
    }

    @Test("values are clamped to sane ranges")
    func clamps() {
        let high = difficulty("CircleSize:99\nApproachRate:99\nSliderMultiplier:99\nHPDrainRate:99\nOverallDifficulty:99")
        let low = difficulty("CircleSize:-4\nApproachRate:-4\nSliderMultiplier:0\nHPDrainRate:-4\nOverallDifficulty:-4")

        #expect(high.cs == 10 && high.ar == 10 && high.hp == 10 && high.od == 10)
        #expect(high.sliderMultiplier == BeatmapDifficulty.sliderMultiplierRange.upperBound)
        #expect(low.cs == 0 && low.ar == 0 && low.hp == 0 && low.od == 0)
        #expect(low.sliderMultiplier == BeatmapDifficulty.sliderMultiplierRange.lowerBound)
    }
}
