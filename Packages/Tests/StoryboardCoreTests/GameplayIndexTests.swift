import Testing

@testable import StoryboardCore

@Suite("Gameplay index")
struct GameplayIndexTests {
    private func map(ar: Double, _ objects: [HitObject]) -> GameplayMap {
        GameplayMap(GameplayFixture.gameplay(ar: ar, objects: objects))
    }

    @Test("AR 9: visible from start - 600 through end + fade-out (S1.8a)")
    func ar9Window() {
        let m = map(ar: 9, [GameplayFixture.circle(at: 1000)])
        #expect(m.index.candidates(at: 399).isEmpty)
        #expect(m.index.candidates(at: 400) == [0])
        #expect(m.index.candidates(at: 1000) == [0])
        #expect(m.index.candidates(at: 1000 + GameplayMap.fadeOut) == [0])
        #expect(m.index.candidates(at: 1000 + GameplayMap.fadeOut + 1).isEmpty)
    }

    @Test("a slider stays visible until its own end (S1.8a)")
    func sliderEnd() {
        let m = map(ar: 9, [GameplayFixture.slider(at: 1000)])
        let end = m.objects[0].endTime
        #expect(end == 1500)
        #expect(m.index.candidates(at: end) == [0])
        #expect(m.index.candidates(at: end + GameplayMap.fadeOut) == [0])
        #expect(m.index.candidates(at: end + GameplayMap.fadeOut + 1).isEmpty)
    }

    @Test("AR 0 and AR 10 use their own preempt (S1.8b)")
    func arBoundaries() {
        let slow = map(ar: 0, [GameplayFixture.circle(at: 5000)])
        #expect(slow.index.candidates(at: 5000 - 1800) == [0])
        #expect(slow.index.candidates(at: 5000 - 1801).isEmpty)
        let fast = map(ar: 10, [GameplayFixture.circle(at: 5000)])
        #expect(fast.index.candidates(at: 5000 - 450) == [0])
        #expect(fast.index.candidates(at: 5000 - 451).isEmpty)
    }

    @Test("a 50k-object window returns only the window and does sublinear work (S1.8c)")
    func largeMap() {
        let objects = (0 ..< 50_000).map { GameplayFixture.circle(at: Double($0) * 100) }
        // Built straight from placed objects: the cap on parsed objects is a
        // parser matter, the index must hold up on its own.
        let m = GameplayMap(GameplayFixture.gameplay(ar: 9, objects: objects))
        var steps = 0
        let hits = m.index.candidates(at: 2_500_000, steps: &steps)
        let expected = objects.indices.filter { m.objects[$0].isVisible(at: 2_500_000) }
        #expect(hits == expected)
        #expect(hits.count < 20)
        #expect(steps < 200)
    }

    @Test("overlapping long sliders are all returned while active (S1.8d)")
    func overlappingSliders() {
        let objects = (0 ..< 5).map {
            GameplayFixture.slider(at: 1000 + Double($0) * 10, slides: 40)
        }
        let m = map(ar: 9, objects)
        #expect(m.index.candidates(at: 10_000) == [0, 1, 2, 3, 4])
    }

    @Test("a spinner spanning hours is found without filling thousands of buckets")
    func longObject() {
        let m = map(ar: 9, [GameplayFixture.spinner(from: 0, to: 9_000_000), GameplayFixture.circle(at: 5_000_000)])
        #expect(m.index.candidates(at: 4_999_999) == [0, 1])
        #expect(m.index.candidates(at: 8_999_999) == [0])
    }

    @Test("matches a brute-force oracle over seeded random maps")
    func oracle() {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        for seed in 0 ..< 5 {
            let objects: [HitObject] = (0 ..< 300).map { _ in
                let t = (next() * 60_000).rounded()
                switch next() {
                case ..<0.5: return GameplayFixture.circle(at: t)
                case ..<0.9: return GameplayFixture.slider(at: t, slides: 1 + Int(next() * 6))
                default: return GameplayFixture.spinner(from: t, to: t + next() * 8000)
                }
            }
            let m = map(ar: Double(seed * 2 + 1), objects)
            for _ in 0 ..< 200 {
                let t = (next() * 70_000 - 5_000).rounded()
                let expected = m.objects.indices.filter { m.objects[$0].isVisible(at: t) }
                #expect(m.index.candidates(at: t) == expected, "seed \(seed) t \(t)")
            }
        }
    }

    @Test("an empty map and non-finite times yield nothing and never trap")
    func hostileTimes() {
        let empty = map(ar: 9, [])
        #expect(empty.index.candidates(at: 0).isEmpty)
        let m = map(ar: 9, [GameplayFixture.circle(at: 1000)])
        #expect(m.index.candidates(at: .nan).isEmpty)
        #expect(m.index.candidates(at: .infinity).isEmpty)
        #expect(m.index.candidates(at: 1e300).isEmpty)
        #expect(m.index.candidates(at: -1e300).isEmpty)
    }
}
