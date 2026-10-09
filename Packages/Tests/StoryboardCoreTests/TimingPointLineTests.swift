import Testing

@testable import StoryboardCore

@Suite("TimingPointLine")
struct TimingPointLineTests {
    @Test("a red line reads tempo, meter, flags and kiai")
    func redLine() throws {
        let line = try #require(TimingPointLine.parse("1000.4,500,3,1,0,60,1,1"))

        #expect(line.time == 1000)
        #expect(line.beatLength == 500)
        #expect(line.meter == 3)
        #expect(line.isUninherited)
        #expect(line.kiai)
    }

    @Test("a green line is inherited and keeps its negative beatLength")
    func greenLine() throws {
        let line = try #require(TimingPointLine.parse("2000,-50,4,1,0,60,0,0"))

        #expect(!line.isUninherited)
        #expect(line.beatLength == -50)
        #expect(!line.kiai)
    }

    @Test("old files without the uninherited flag are red")
    func missingFlagIsRed() throws {
        let line = try #require(TimingPointLine.parse("0,400"))

        #expect(line.isUninherited)
        #expect(line.meter == 4)
    }

    @Test("lines that cannot be read are nil, never a trap")
    func malformed() {
        #expect(TimingPointLine.parse("") == nil)
        #expect(TimingPointLine.parse("1000") == nil)
        #expect(TimingPointLine.parse("nan,500") == nil)
        #expect(TimingPointLine.parse("inf,500") == nil)
        #expect(TimingPointLine.parse("1e308,500")?.time == 1e308)
    }
}
