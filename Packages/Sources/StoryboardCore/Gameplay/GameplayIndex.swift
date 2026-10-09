import Foundation

/// One hit object with everything the overlay derives from the difficulty and
/// timing, computed once.
public struct PlacedObject: Sendable, Equatable {
    public let index: Int
    public let object: HitObject
    /// When the object stops being "live": the hit for a circle, the end of
    /// the last slide, the spinner's end.
    public let endTime: Double
    /// Milliseconds of one pass over a slider; 0 for other kinds.
    public let spanDuration: Double
    public let radius: Double
    public let preempt: Double

    /// First instant the object is drawn.
    public var visibleStart: Double { object.time - preempt }
    /// Last instant: the end plus the fade-out.
    public var visibleEnd: Double { endTime + GameplayMap.fadeOut }

    public func isVisible(at time: Double) -> Bool {
        time >= visibleStart && time <= visibleEnd
    }
}

/// Which objects are on screen at a time, without scanning them all.
///
/// Buckets of a second, like `StoryboardResolver.LiveIndex`: an object lives
/// over a SPAN, so a sorted-by-start array with a cursor is defeated by one
/// long slider. The exception is an object whose span would fill more than
/// ``maxBucketsPerObject`` buckets (an hour-long spinner from a hostile file):
/// those sit in a small side list that every query checks, instead of
/// multiplying their cost by thousands of buckets.
public struct GameplayIndex: Sendable {
    private static let bucketSpan: Double = 1000
    private static let maxBucketsPerObject = 64
    /// Times are clamped here so converting to a bucket can never trap.
    private static let timeLimit: Double = 1e8

    public let objects: [PlacedObject]
    private let buckets: [Int: [Int]]
    private let long: [Int]

    public init(_ objects: [PlacedObject]) {
        self.objects = objects
        var buckets: [Int: [Int]] = [:]
        var long: [Int] = []
        for (position, placed) in objects.enumerated() {
            let lo = Self.clamp(placed.visibleStart), hi = Self.clamp(placed.visibleEnd)
            let first = Int((lo / Self.bucketSpan).rounded(.down))
            let last = Int((hi / Self.bucketSpan).rounded(.down))
            if last - first >= Self.maxBucketsPerObject {
                long.append(position)
            } else {
                for bucket in first ... last { buckets[bucket, default: []].append(position) }
            }
        }
        self.buckets = buckets
        self.long = long
    }

    private static func clamp(_ time: Double) -> Double {
        min(max(time, -timeLimit), timeLimit)
    }

    /// Positions (in `objects`, ascending) of the objects visible at `time`.
    ///
    /// - Parameter steps: when given, counts the objects examined. A probe for
    ///   tests; `nil` in production.
    public func candidates(at time: Double, steps: UnsafeMutablePointer<Int>? = nil) -> [Int] {
        guard time.isFinite, abs(time) <= Self.timeLimit else { return [] }
        var found: [Int] = []
        let bucket = Int((time / Self.bucketSpan).rounded(.down))
        for position in buckets[bucket] ?? [] {
            steps?.pointee += 1
            if objects[position].isVisible(at: time) { found.append(position) }
        }
        for position in long {
            steps?.pointee += 1
            if objects[position].isVisible(at: time) { found.append(position) }
        }
        // Long objects were appended after the bucketed ones.
        return long.isEmpty ? found : found.sorted()
    }
}
