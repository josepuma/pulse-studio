import Testing

@testable import StoryboardCore

@Suite("Mesh cache")
struct MeshCacheTests {
    @Test("the same slider requested at 100 times is tessellated once (S2.6a)")
    func once() throws {
        let m = GameplayMap(GameplayFixture.gameplay(objects: [GameplayFixture.slider(at: 1000, slides: 2)]))
        #expect(m.meshBuildCount == 0, "nothing is built until a slider is asked for")
        var first: [SliderMeshVertex] = []
        for i in 0 ..< 100 {
            let mesh = try #require(m.mesh(forObject: 0, at: 500 + Double(i) * 10))
            if i == 0 { first = mesh }
            #expect(mesh == first)
        }
        #expect(m.meshBuildCount == 1)
    }

    @Test("circles and spinners have no mesh")
    func noMesh() {
        let m = GameplayMap(GameplayFixture.gameplay(objects: [
            GameplayFixture.circle(at: 100), GameplayFixture.spinner(from: 200, to: 900),
        ]))
        #expect(m.mesh(forObject: 0, at: 100) == nil)
        #expect(m.mesh(forObject: 1, at: 200) == nil)
        #expect(m.mesh(forObject: 99, at: 200) == nil)
        #expect(m.meshBuildCount == 0)
    }

    @Test("a mesh is built in storyboard space (S2.3c)")
    func mapped() throws {
        let m = GameplayMap(GameplayFixture.gameplay(objects: [GameplayFixture.slider(at: 1000)]))
        let mesh = try #require(m.mesh(forObject: 0, at: 1000))
        let radius = BeatmapDifficultyMath.radius(cs: 4)
        let headX = PlayfieldMapping.storyboard(PlayfieldPoint(x: 100, y: 100)).x
        #expect(abs(Double(mesh.map(\.x).min()!) - (headX - radius)) < 1e-2)
    }

    @Test("switching difficulty means a new map and a cold cache (S2.6b)")
    func invalidation() throws {
        let objects = [GameplayFixture.slider(at: 1000)]
        let a = GameplayMap(GameplayFixture.gameplay(ar: 9, objects: objects))
        _ = a.mesh(forObject: 0, at: 1000)
        let b = GameplayMap(GameplayFixture.gameplay(ar: 9, objects: objects))
        #expect(b.meshBuildCount == 0)
        _ = b.mesh(forObject: 0, at: 1000)
        #expect(b.meshBuildCount == 1)
        #expect(a.meshBuildCount == 1)
    }

    @Test("the cache holds at most the cap and evicts the farthest in time, sparing visible ones")
    func eviction() throws {
        let cap = GameplayMap.meshCacheCapacity
        #expect(cap == 512)
        let count = cap + 50
        let objects = (0 ..< count).map { GameplayFixture.slider(at: Double($0) * 10_000) }
        let m = GameplayMap(GameplayFixture.gameplay(objects: objects))
        // Visit everything in order, "now" following the object.
        for i in 0 ..< count { _ = m.mesh(forObject: i, at: Double(i) * 10_000) }
        #expect(m.meshBuildCount == count)
        #expect(m.cachedMeshCount <= cap)
        // The latest ones are still warm (nearest to now), the earliest were evicted.
        let before = m.meshBuildCount
        _ = m.mesh(forObject: count - 1, at: Double(count - 1) * 10_000)
        #expect(m.meshBuildCount == before)
        _ = m.mesh(forObject: 0, at: Double(count - 1) * 10_000)
        #expect(m.meshBuildCount == before + 1)
    }

    @Test("a visible mesh is never the one evicted while something farther exists")
    func visibleSpared() throws {
        let cap = GameplayMap.meshCacheCapacity
        // Object 0 is visible "now"; the rest are far in the future.
        var objects = [GameplayFixture.slider(at: 1000)]
        objects += (1 ... cap).map { GameplayFixture.slider(at: 1_000_000 + Double($0) * 10_000) }
        let m = GameplayMap(GameplayFixture.gameplay(objects: objects))
        _ = m.mesh(forObject: 0, at: 1000)
        for i in 1 ... cap { _ = m.mesh(forObject: i, at: 1000) }
        let before = m.meshBuildCount
        _ = m.mesh(forObject: 0, at: 1000)
        #expect(m.meshBuildCount == before, "the visible slider was evicted")
    }
}
