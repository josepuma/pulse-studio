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

    static let circleColor = SIMD4<Float>(0.40, 0.72, 1.00, 1)
    /// Slider body at the rim (lighter) and at the centreline (darker, so the
    /// white border contrasts). Flat colours; the gradient between is the only shading.
    static let sliderColor = SIMD4<Float>(0.28, 0.50, 0.80, 1)
    static let sliderInnerColor = SIMD4<Float>(0.14, 0.27, 0.50, 1)
    static let borderColor = SIMD4<Float>(1, 1, 1, 1)
    static let approachColor = SIMD4<Float>(1, 1, 1, 1)
    static let ballColor = SIMD4<Float>(1, 0.93, 0.55, 1)
    static let arrowColor = SIMD4<Float>(1, 1, 1, 1)
    static let spinnerColor = SIMD4<Float>(1, 0.40, 0.67, 1)

    /// Share of the slider radius the white border takes, from the rim inwards.
    /// osu!lazer's `DrawableSliderPath.BORDER_PORTION` is 0.128 (from memory of
    /// the source; not verifiable from this environment, so treat as unconfirmed).
    static let sliderBorderWidth: Float = 0.128
    /// The ball and the reverse arrow relative to the object radius.
    static let ballScale: Double = 0.9
    static let arrowScale: Double = 0.6
}
