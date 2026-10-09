import StoryboardCore
import simd

/// How the gameplay overlay looks. A flat, skinless read of the objects: the
/// point is to see WHERE and WHEN they are against the storyboard, not to imitate
/// a skin. Lives here because this target cannot import the design system.
enum GameplayOverlayStyle {
    /// Bodies (circle, slider, ball, arrows, spinner) keep this share of the fade
    /// alpha so the storyboard stays readable underneath. Borders and rims do NOT:
    /// they are drawn at the full fade alpha so they read as an opaque ring.
    static let bodyOpacity: Double = 0.6
    /// Approach circles are thin lines; they get their own, higher, opacity.
    static let approachOpacity: Double = 0.9

    /// Fallbacks for an object with no combo colour (the approach pass).
    static let circleColor = SIMD4<Float>(0.40, 0.72, 1.00, 1)
    /// Slider body at the rim (lighter) and at the centreline (darker, so the
    /// white border contrasts). Flat colours; the gradient between is the only shading.
    static let sliderColor = SIMD4<Float>(0.28, 0.50, 0.80, 1)
    static let sliderInnerColor = SIMD4<Float>(0.14, 0.27, 0.50, 1)
    /// How much of the combo colour is left at the slider centreline.
    static let innerShade: Float = 0.5
    static let borderColor = SIMD4<Float>(1, 1, 1, 1)
    static let approachColor = SIMD4<Float>(1, 1, 1, 1)
    static let ballColor = SIMD4<Float>(1, 0.93, 0.55, 1)
    static let arrowColor = SIMD4<Float>(1, 1, 1, 1)
    static let spinnerColor = SIMD4<Float>(1, 0.40, 0.67, 1)
    /// Kiai fountain stars: lazer's texture is white, drawn additively.
    static let fountainColor = SIMD4<Float>(1, 1, 1, 1)

    /// Share of the slider radius the white border takes, from the rim inwards.
    /// Matches osu!lazer's `DrawableSliderPath.BORDER_PORTION` (0.128f, checked
    /// against ppy/osu master).
    static let sliderBorderWidth: Float = 0.128
    /// The ball and the reverse arrow relative to the object radius.
    static let ballScale: Double = 0.9
    static let arrowScale: Double = 0.6

    /// A combo colour as drawn: the 0-255 bytes divided by 255 and nothing else.
    /// The pipeline is not sRGB (osu! composes in gamma space), so no linearising.
    static func tint(_ colour: ComboColour) -> SIMD4<Float> {
        SIMD4<Float>(Float(colour.r) / 255, Float(colour.g) / 255, Float(colour.b) / 255, 1)
    }

    /// The slider centreline: the combo colour mixed toward black, so the white
    /// border still contrasts.
    static func innerTint(_ colour: ComboColour) -> SIMD4<Float> {
        let base = tint(colour)
        return SIMD4<Float>(base.x * innerShade, base.y * innerShade, base.z * innerShade, 1)
    }
}
