import Foundation

/// Where osu!'s 512x384 playfield sits on the storyboard canvas.
///
/// The ONE place that knows: the overlay's instances, slider meshes and any
/// future picking all go through ``storyboard(_:)``.
public enum PlayfieldMapping {
    /// The playfield centred in the 640x480 storyboard space: (640 - 512) / 2
    /// and (480 - 384) / 2. Scale is 1: a playfield unit is a storyboard unit.
    public static let origin = PlayfieldPoint(x: 64, y: 48)

    /// Extra vertical shift on top of the centring.
    ///
    /// PROVISIONAL AND UNVERIFIED: 0 is the neutral placeholder, not a
    /// measurement. It must be settled against a real osu! stable capture
    /// (task 3.1, pending) and then pinned by a test whose expected value
    /// comes from that capture. Until then nothing may claim it is osu!'s.
    public static let verticalOffset: Double = 0

    /// What the wide (854x480) canvas adds to a storyboard x. Mirrors
    /// `OsuCanvas.xOffset` (a Rendering test cross-checks them): Core cannot
    /// import the renderer.
    public static let wideCanvasXOffset: Double = 107

    /// The whole translation, centring plus the (provisional) vertical term.
    public static var offset: PlayfieldPoint {
        PlayfieldPoint(x: origin.x, y: origin.y + verticalOffset)
    }

    /// Playfield → storyboard coordinates (x from -107 to 747).
    public static func storyboard(_ point: PlayfieldPoint) -> PlayfieldPoint {
        PlayfieldPoint(x: point.x + offset.x, y: point.y + offset.y)
    }

    /// Playfield → wide-canvas coordinates.
    public static func canvas(_ point: PlayfieldPoint) -> PlayfieldPoint {
        let sb = storyboard(point)
        return PlayfieldPoint(x: sb.x + wideCanvasXOffset, y: sb.y)
    }
}
